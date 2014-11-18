#!/opt/local/bin/ruby1.9

require 'nokogiri'
require 'open-uri'
require 'erb'
require 'ostruct'

$html_root="."

class Address
  attr_reader :type, :id, :lat, :lon, :name, :leisure
  def initialize(xml)
    @type = xml.name
    @id = xml.attr('id')
    if @type == 'node' then
      @lat = xml.attr('lat')
      @lon = xml.attr('lon')
      @edit = "http://www.openstreetmap.org/edit?editor=id&node=#{@id}#map=19/#{@lat}/#{@lon}"
      @view = "http://www.openstreetmap.org/node/#{@id}"
    elsif @type == 'way'
      @lat = xml.at_xpath('center').attr('lat')
      @lon = xml.at_xpath('center').attr('lon')
      @edit = "http://www.openstreetmap.org/edit?editor=id&way=#{@id}#map=19/#{@lat}/#{@lon}"
      @view = "http://www.openstreetmap.org/way/#{@id}"
    elsif @type == 'relation'
      @edit = "http://www.openstreetmap.org/edit?editor=id&relation=#{@id}#map=19/#{@lat}/#{@lon}"
      @view = "http://www.openstreetmap.org/relation/#{@id}"
    else
      raise "Unknown type #{@type}"
    end
    @name = get(xml,'name')
    @housenumber = get(xml,'addr:housenumber')
    @street = get(xml,'addr:street')
    @website = (get(xml,'website') or get(xml,'contact:website'))
    @wikipedia = get(xml,'wikipedia')
    @cuisine = get(xml,'cuisine')
    @organic = get(xml,'organic') == 'yes'
    @wifi = get(xml,'internet_access') =~ /yes|wlan/
    @beers = get(xml,'brewery')
    @description = get(xml,'description')
    @opening_hours = get(xml,'opening_hours')
    @phone = (get(xml,'phone') or get(xml, 'contact:phone'))
    @leisure = get(xml,'leisure')
  end
  def ranking
    score=0
    score += 1 if @type == 'way'
    score += 5 if @type == 'relation'
    score += 1 unless @housenumber.nil?
    score += 0.5 unless @street.nil?
    score += 5 unless @wikipedia.nil?
    score += 2 unless @descrition.nil?
    score += 1 unless @website.nil?
    score += 2 unless @opening_hours.nil?
    score
  end
  def get(xml, key)
    node = xml.at_xpath("tag[@k='#{key}']")
    if node then
      return node.attr('v')
    end
    return nil
  end
  def detail
    if @cuisine then
      cuisine = case @cuisine
                when "burger"
                  "burgers"
                when "bagel"
                  "bagels"
                else
                  @cuisine
                end
      "#{cuisine.capitalize}"
    else
      nil
    end
  end
  def html
    o = "<a href=\"#{@view}\" title=\"View #{@name} on OpenStreetMap.org\" target=\"osm\"><strong>#{@name}</strong></a><br />\n"
    d = detail
    if d then
      o += detail + "<br />\n"
    end
    if @description then
      o += @description + "<br />\n"
    end
    if @beers then
      o += "<i>Beers on tap:</i><ul>\n"
      @beers.split(';').each do |beer|
        o+= "<li>#{beer}</li>\n"
      end
      o += "</ul>\n"
    end
    if @street then
      o += "#{@housenumber} #{@street}<br />\n"
    end
    # o += " <small><a href=\"http://www.google.com/maps/place/#{@name}/@#{@lat},#{@lon}\" target=\"map\">map</a><br />\n</small>"
    # o += " <small><a href=\"https://maps.google.com?ll=#{@lat},#{@lon}&q=#{@name}\" target=\"map\">map</a><br />\n</small>"
    if @phone then
      o += "<a href=\"tel:#{@phone}\">#{@phone}</a><br />\n"
    end
    if @website then
      if @website =~ /^www./ then
        uri = URI('http://' + @website)
      else
        uri = URI(@website)
      end
      if uri.host then
        o += "<a href=\"#{@website}\">#{uri.host.gsub(/^www./,'')}</a>&nbsp;"
      else
        $stderr.puts "Invalid URL: #{@website} #{@edit}"
      end
    end
    if @opening_hours then
      o += "Open #{@opening_hours}&nbsp;&nbsp;"
    end
    if @organic then
      o += "<img src=\"#{$html_root}/images/organic32.png\" alt_text=\"Organic\" />&nbsp;"
    end
    if @wifi then
      o += "<img src=\"#{$html_root}/images/wifi32.png\" alt_text=\"Wifi\">\&nbsp;"
    end
    # o += "<small><a href=\"#{@edit}\" title=\"Edit #{@name} on OpenStreetMap\" target=\"edit\">edit</a></small>"
    o
  end
  def sortkey
    @name.downcase.gsub(/^the /,'')
  end
end

class Cafe < Address
  def initialize(xml)
    super(xml)
  end
  def detail
    ""
  end
end

class Church < Address
  attr_reader :religion, :denomination
  def initialize(xml)
    super(xml)
    @religion = get(xml,'religion')
    if @religion then
      @religion.capitalize!
    end
    @denomination = get(xml,'denomination')
    if @denomination then
      @denomination.capitalize!
    end
  end
  def detail
    [@religion,@denomination].compact.join(" : ")
  end
  def sortkey
    [@religion || 'ZZZ', @denomination || 'ZZZ', @name.downcase.gsub(/^the /,'')]
  end
end

def parse(file, type)
  doc = Nokogiri.XML(File.open(file))
  output = []
  doc.xpath("//node").each do |node| 
    a = type.new(node)
    output << a
  end
  doc.xpath("//way").each do |node| 
    a = type.new(node)
    output << a
  end
  doc.xpath("//relation").each do |node| 
    a = type.new(node)
    output << a
  end
  return output.sort_by { |a| a.sortkey }
end

def render(city_dir, city, state, place, root)
  $html_root=root
  dining = parse(File.join(city_dir,'dining.xml'), Address)
  cafes = parse(File.join(city_dir,'cafes.xml'), Cafe)
  icecream = parse(File.join(city_dir,'icecream.xml'), Address)

  entertainment = parse(File.join(city_dir,'entertainment.xml'), Address)
  arts = parse(File.join(city_dir,'arts.xml'), Address)
  leisure = parse(File.join(city_dir,'leisure.xml'), Address)
  golf = []
  leisure.delete_if {|v| golf << v if v.leisure == 'golf_course'}
  playgrounds = []
  leisure.delete_if {|v| playgrounds << v if v.leisure == 'playground'}
  leisure.delete_if {|v| v.type == 'node'}

  hotels = parse(File.join(city_dir,'hotels.xml'), Address)
  churches = parse(File.join(city_dir,'churches.xml'), Church)
  #churches.each { |p| puts "#{p.name} : #{p.ranking}" }
  churches.delete_if { |p| p.ranking == 0 }

  if dining.size + cafes.size + icecream.size + entertainment.size + arts.size + leisure.size + golf.size + playgrounds.size + hotels.size + churches.size == 0 then
    nil
  else
    renderer = ERB.new(File.read('template/city.erb'))
    renderer.result(binding)
  end
end

def render_state(state, state_html, places, root)
  $html_root=root
  counties = places.values.collect { |p| p.county }.uniq
  renderer = ERB.new(File.read('template/state.erb'))
  out = renderer.result(binding)
  File.open(state_html, 'w') { |f| f.print(out) }
end
def render_index(states, output)
  root='.'
  states=states
  renderer = ERB.new(File.read('template/index.erb'))
  out = renderer.result(binding)
  File.open(output, 'w') { |f| f.print(out) }
end
