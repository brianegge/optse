#!/usr/bin/ruby1.9.1 --disable-gems

require 'rubygems'
require 'active_support/inflector'

require_relative 'render'
require 'nokogiri'
require 'open-uri'
require 'erb'
require 'fileutils'
require 'tempfile'
require 'json'
require 'filecache'

EMAIL='brianegge@gmail.com'
ROOT_DIR=File.dirname(File.dirname(__FILE__))
QUERY_DIR=File.join(ROOT_DIR, 'bin')
DATA_DIR=File.join(ROOT_DIR, 'data')
HTML_DIR=File.join(ROOT_DIR, 'html')
STATES=['Alabama', 
  'Alaska', 
  'Arizona', 
  'Arkansas', 
 # 'California',
  'Colorado', 
  'Connecticut', 
  'Delaware',
  'Florida',
  'Georgia',
  'Hawaii',
  'Idaho',
  'Illinois',
  'Indiana',
  'Iowa',
  'Kansas',
  'Kentucky',
  'Louisiana',
  'Wyoming']

FileUtils.mkdir_p DATA_DIR
$placecache = FileCache.new(domain='places', root_dir='data/cache')

class City
  attr_reader :type, :id, :name, :edit, :view
  attr_accessor :empty
  alias_method :empty?, :empty
  def initialize(xml)
    @xml = xml
    @type = xml.name
    @id = xml.attr('id')
    @name = ( get(xml,'name') or get(xml,'place_name') or get(xml,'tiger:NAME') or raise ArgumentError,"Can't find place name in #{xml}" )
    @county = get(xml,'is_in:county')
    @lat = xml.at_xpath('center').attr('lat')
    @lon = xml.at_xpath('center').attr('lon')
    @edit = "http://www.openstreetmap.org/edit?editor=id&#{@type}=#{@id}#map=19/#{@lat}/#{@lon}"
    @view = "http://www.openstreetmap.org/#{@type}/#{@id}"
    # TODO, use label center if set
  end
  def get(xml, key)
    node = xml.at_xpath("tag[@k='#{key}']")
    if node then
      return node.attr('v')
    end
    return nil
  end
  def ref
    if @type == 'way' then
      2400000000 + @id.to_i
    elsif @type == 'relation' then
      3600000000 + @id.to_i
    else
      @id.to_i
    end
  end
  def center
    "#{@lat},#{@lon}"
  end
  def wikivoyage
    if @wikivoyage.nil? then
      url="http://en.wikivoyage.org/w/api.php?action=query&list=geosearch&gsradius=10000&gscoord=#{@lat}%7C#{@lon}&format=json&continue="
      json = JSON.load(open(url))
      # puts JSON.pretty_generate(json)
      if json and json['query']['geosearch'].size > 0 then
        @wikivoyage = json['query']['geosearch'][0]['title']
      end
    end
    @wikivoyage
  end
  def wikipedia
    n = get(@xml,'wikipedia')
    if n then
      return n.split(':')[1]
    end
  end
  def wikipedia_url
    w = get(@xml,'wikipedia').split(':')
    return "http://#{w[0]}.wikipedia.org/wiki/#{w[1].gsub(/_/,' ')}"
  end
  def <=> other
    self.name <=> other.name
  end
end

class Place
  attr_reader :display_name, :county, :city, :state, :link, :boundingbox
  class << self
    protected :new
    def city(city, state)
      url="http://nominatim.openstreetmap.org/search?format=json&city=#{URI::encode(city)}&state=#{URI::encode(state)}&email=#{URI::encode(EMAIL)}&addressdetails=1&limit=1"
      json = $placecache.get(url)
      if json.nil? then
        json = JSON.load(open(url))
        $placecache.set(url,json)
        sleep 1
      end
      raise "Failed to open #{url}" if json.nil?
      raise ArgumentError, "No results for #{url}" if (json.empty? or json[0].nil?)
      new(json[0])
    end
    def state(state)
      url="http://nominatim.openstreetmap.org/search?format=json&state=#{URI::encode(state)}&email=#{URI::encode(EMAIL)}&addressdetails=1&limit=1"
      json = $placecache.get(url)
      if json.nil? then
        json = JSON.load(open(url))
        $placecache.set(url,json)
        sleep 1
      end
      new(json[0])
    end
  end

  def initialize(json)
    @place_id = json['place_id']
    @osm_id = json['osm_id'].to_i
    @osm_type = json['osm_type']
    @link = "http://www.openstreetmap.org/#{@osm_type}/#{@osm_id}"
    @display_name = (json['display_name'] or raise "No display_name is #{json}")
    @class = json['class']
    @type = json['type']
    @boundingbox = json['boundingbox']
    @county = json['address']['county']
    @city = (json['address']['city'] or json['address']['suburb'] or json['address']['town'] or json['address']['village'] or json['address']['hamlet'])
    @state = json['address']['state']
  end
  def ref
    if @osm_type == 'way' then
      2400000000 + @osm_id
    elsif @osm_type == 'relation' then
      3600000000 + @osm_id
    else
      @osm_id
    end
  end
  def center
    lat=@boundingbox[0].to_f + (@boundingbox[1].to_f - @boundingbox[0].to_f) / 2.0
    lon=@boundingbox[2].to_f + (@boundingbox[3].to_f - @boundingbox[2].to_f) / 2.0
    "#{lat},#{lon}"
  end
end
#
#STATIC_MAP='http://staticmap.openstreetmap.de/staticmap.php'
STATIC_MAP='http://optse.com/staticmaplite/staticmap.php'
DEGREES_IN_CIRCLE=360.0
def banner(title, place, output)
  puts "rendering banner #{title}"
  lngDiff = (place.boundingbox[2].to_f - place.boundingbox[3].to_f).abs
  puts "Center: #{place.center}, Bounds: #{place.boundingbox}, Diff: #{lngDiff}"
  if (lngDiff < DEGREES_IN_CIRCLE / 2 ** 20) then
    zoomLevel = 21
  else
    zoomLevel =  (-1*( (Math.log(lngDiff)/Math.log(2)) - (Math.log(360)/Math.log(2)))).to_i + 2
    if (zoomLevel < 1) then
      zoomLevel = 1
    end
  end
  puts "Zoom: #{zoomLevel}"
  city_map=Tempfile.new(['map','.png']).path
  city_text=Tempfile.new(['text','.png']).path
  city_text2=Tempfile.new(['text2','.png']).path
  %x{wget --quiet -O #{city_map} "#{STATIC_MAP}?center=#{place.center}&zoom=#{zoomLevel}&size=900x200&maptype=mapnik"}
  `convert -background none -gravity center -stroke grey -size 900x200 -fill black  -font Century-Schoolbook-Roman -blur 0x5 -fill black "label:#{title}" #{city_text}`
  `convert -background none -gravity center -stroke grey -size 900x200 -fill black  -font Century-Schoolbook-Roman "label:#{title}"  #{city_text2}`
  `convert -page 0 #{city_map} -page +5+5 #{city_text} -page -0 #{city_text2} -layers flatten #{output}`
end

STATES.each do |state|
  if ARGV[0] and ARGV[0].downcase != state.downcase then
    next
  end
  state_xml_file=File.join(DATA_DIR,state.parameterize + ".xml")
  if !File.exist?(state_xml_file) then
    place = Place.state(state)
    input=File.join(QUERY_DIR,"states.xml")
    template = Nokogiri.XML(File.open(input))
    node = template.at_xpath("//id-query")
    node.attributes['ref'].value = place.ref.to_s
    query=Tempfile.new('query')
    File.open(query.path, 'w') { |f| f.print(template.to_xml) }
    puts `wget --no-verbose --user-agent="brianegge@gmail.com" -O "#{state_xml_file}" --post-file="#{query.path}" "http://overpass-api.de/api/interpreter"`
    sleep 1
  else
    puts "#{state_xml_file} exists"
  end
  doc = Nokogiri.XML(File.open(state_xml_file))
  cities = []
  doc.xpath("//relation").each do |node| 
    begin
      a = City.new(node)
      cities << a
    rescue ArgumentError
      puts "ignoring city without name #{node.to_xml}"
    end
  end
  doc.xpath("//way").each do |node| 
    a = City.new(node)
    cities << a
  end
  city_names = cities.collect { |c| c.name }
  dups = city_names.select { |e| city_names.count(e) > 1 }.uniq
  if not dups.empty? then
    $stderr.puts "Duplicate cities in #{state}: #{dups.sort}"
  end
  state_dir=File.join(DATA_DIR, state.parameterize) 
  state_html=File.join(HTML_DIR, state.parameterize, 'index.html')
  FileUtils.mkdir_p state_dir
  places = {}
  cities.each do |city_node|
    city = city_node.name
    city_dir=File.join(state_dir, city.parameterize) 
    FileUtils.mkdir_p city_dir
    city_html_dir=File.join(HTML_DIR, state.parameterize, city.parameterize)
    city_html=File.join(city_html_dir,'index.html')
    city_empty=File.join(city_dir,'empty')
    place = nil
    if File.exist?(city_empty) then
      city_node.empty = true
    elsif File.exist?(city_html) and File.mtime(city_html) > File.mtime(city_dir) then
    else
      FileUtils.mkdir_p city_html_dir
      begin 
        place = Place.city(city, state)
      rescue ArgumentError
        puts "ignoring #{city}, #{state}"
        FileUtils.touch(city_empty)
        city_node.empty = true
        next
      end
      places[city] = place
      puts place.display_name

      %w(dining cafes icecream entertainment arts leisure churches hotels).each do |t|
        city_out=File.join(city_dir, t + ".xml")
        if !File.exist?(city_out) then
          puts "Getting #{city_out}"
          input=File.join(QUERY_DIR,t + ".xml")
          template = Nokogiri.XML(File.open(input))
          node = template.at_xpath("//id-query")
          node.attributes['ref'].value = city_node.ref.to_s
          out=Tempfile.new(t)
          File.open(out.path, 'w') { |f| f.print(template.to_xml) }
          `wget --no-verbose --user-agent="#{EMAIL}" -O "#{city_out}" --post-file="#{out.path}" "http://overpass-api.de/api/interpreter"` or raise "Failed to query #{city}/#{t}"
          sleep 1
        end
      end
      s = render_city(city_dir, city_node, state, place, "../..")
      if s.nil? then
        city_node.empty = true
        FileUtils.touch(city_empty)
      else
        File.open(city_html, 'w') { |f| f.print(s) }
      end
    end
    city_banner=File.join(city_html_dir,'banner.png')
    if not File.exist?(city_banner) then
      if city_node.empty? then
        next
      end
      place ||= Place.city(city, state)
      banner(city, place, city_banner)
    end
  end
  empty_cities=[]
  if not File.exist?(state_html) or File.mtime(state_xml_file) > File.mtime(state_html) then
    puts "Rendering state #{state}"
    cities.each do |city_node|
      city = city_node.name
      if city_node.empty? then
        puts "Not including #{city} in index because it is empty"
        places.delete(city)
        empty_cities << city_node
      elsif places[city].nil? then
        places[city] = Place.city(city, state)
        puts "Added #{city}"
      end
    end
    places.each do |k,v| 
      if v.county.nil? then
        p v
        raise "City #{k} has no county information"
      elsif v.city.nil? then
        p v
        raise "City #{k} has no city information"
      end
    end
    render_state(state, state_html, places, empty_cities, '..')
  end
  state_banner=File.join(HTML_DIR, state.parameterize, 'banner.png')
  if not File.exist?(state_banner) then
    place = Place.state(state)
    banner(state, place, state_banner)
  end
end
index_html=File.join(HTML_DIR, 'index.html')
render_index(STATES,index_html) 
