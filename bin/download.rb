#!/opt/local/bin/ruby1.9

require_relative 'generate'
require 'nokogiri'
require 'open-uri'
require 'erb'
require 'active_support/inflector'
require 'fileutils'
require 'tempfile'
require 'json'

EMAIL='brianegge@gmail.com'
ROOT_DIR=File.dirname(File.dirname(__FILE__))
QUERY_DIR=File.join(ROOT_DIR, 'bin')
DATA_DIR=File.join(ROOT_DIR, 'data')
HTML_DIR=File.join(ROOT_DIR, 'html')

class City
  attr_reader :type, :id, :name
  def initialize(xml)
    @type = xml.name
    @id = xml.attr('id')
    @name = ( get(xml,'name') or get(xml,'place_name') or raise "Can't find place name in #{@id}" )
    @county = get(xml,'is_in:county')
    @lat = xml.at_xpath('center').attr('lat')
    @lon = xml.at_xpath('center').attr('lon')
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
end

class Place
  attr_reader :display_name, :county, :city, :state
  class << self
    protected :new
    def city(city, state)
      json = JSON.load(open("http://nominatim.openstreetmap.org/search?format=json&city=#{URI::encode(city)}&state=#{URI::encode(state)}&email=#{URI::encode(EMAIL)}&addressdetails=1&limit=1"))
      new(json)
    end
    def state(state)
      json = JSON.load(open("http://nominatim.openstreetmap.org/search?format=json&state=#{URI::encode(state)}&email=#{URI::encode(EMAIL)}&addressdetails=1&limit=1"))
      new(json)
    end
  end

  def initialize(json)
    sleep 1
    json = resp[0]
    @place_id = json['place_id']
    @osm_id = json['osm_id'].to_i
    @osm_type = json['osm_type']
    @display_name = (json['display_name'] or raise "No display_name is #{json}")
    @class = json['class']
    @type = json['type']
    @boundingbox = json['boundingbox']
    @county = json['address']['county']
    @city = (json['address']['city'] or json['address']['village'] or json['address']['hamlet'] or raise "No city in #{json}")
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
def banner(title, center, output)
  city_map=Tempfile.new('map')
  city_text=Tempfile.new('text')
  city_text2=Tempfile.new('text2')
  `wget -O #{city_map} "http://staticmap.openstreetmap.de/staticmap.php?center=#{center}&zoom=15&size=900x200&maptype=mapnik"`
  `convert -background none -gravity center -stroke grey -size 900x200 -fill black  -font Century -blur 0x5 -fill black "label:#{title}" #{city_text}`
  `convert -background none -gravity center -stroke grey -size 900x200 -fill black  -font Century "label:#{title}"  #{city_text2}`
  `convert -page 0 #{city_map} -page +5+5 #{city_text} -page -0 #{city_text2} -layers flatten #{output}`
end

STATES=['Connecticut']
STATES.each do |state|
  out=File.join(DATA_DIR,state.parameterize + ".xml")
  if !File.exist?(out) then
    `wget --user-agent="brianegge@gmail.com" -O "#{out}" --post-file="#{QUERY_DIR}/state.xml" "http://overpass-api.de/api/interpreter"` or raise "Failed to query #{state}"
    sleep 1
  else
    puts "#{out} exists"
  end
  doc = Nokogiri.XML(File.open(out))
  cities = []
  doc.xpath("//way").each do |node| 
    a = City.new(node)
    cities << a
  end
  doc.xpath("//relation").each do |node| 
    a = City.new(node)
    cities << a
  end
  state_dir=File.join(DATA_DIR, state.parameterize) 
  state_html=File.join(HTML_DIR, state, 'index.html')
  FileUtils.mkdir_p state_dir
  places = {}
  cities.each do |city_node|
    city = city_node.name
    city_html_dir=File.join(HTML_DIR, state.parameterize, city.parameterize)
    city_html=File.join(city_html_dir,'index.html')
    if not File.exist?(city_html) then
      FileUtils.mkdir_p city_html_dir
      place = Place.city(city, state)
      places[city] = place
      puts place.display_name
      city_dir=File.join(state_dir, city.parameterize) 

      %w(dining cafes icecream entertainment arts leisure churches hotels).each do |t|
        FileUtils.mkdir_p city_dir
        city_out=File.join(city_dir, t + ".xml")
        if !File.exist?(city_out) then
          puts "Getting #{city_out}"
          input=File.join(QUERY_DIR,t + ".xml")
          template = Nokogiri.XML(File.open(input))
          node = template.at_xpath("//id-query")
          node.attributes['ref'].value = city_node.ref.to_s
          out=Tempfile.new(t)
          File.open(out.path, 'w') { |f| f.print(template.to_xml) }
          `wget --user-agent="#{EMAIL}" -O "#{city_out}" --post-file="#{out.path}" "http://overpass-api.de/api/interpreter"` or raise "Failed to query #{city}/#{t}"
          sleep 1
        end
      end
      File.open(city_html, 'w') { |f| f.print(render(city_dir, city, state, place.display_name, "../..")) }

      city_banner=File.join(city_html_dir,'banner.png')
      if not File.exist?(city_banner) then
        banner(city, place.center, city_banner)
      end
    end
  end
  if not File.exist?(state_html) then
    puts "Rendering state #{state}"
    cities.each do |city_node|
      city = city_node.name
      if places[city].nil? then
        places[city] = Place.city(city, state)
      end
    end
  end
  render_state(state, state_html, places, '..')
  state_banner=File.join(HTML_DIR, state, 'banner.png')
  if not File.exist?(state_banner) then
    place = Place.state(state)
    banner(city, place.center, city_banner)
  end
end
index_html=File.join(HTML_DIR, state, 'index.html')
render_index(STATES,index_html) 
