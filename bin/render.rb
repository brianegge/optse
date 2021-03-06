#!/opt/local/bin/ruby1.9

require 'nokogiri'
require 'open-uri'
require 'erb'
require 'ostruct'
require 'geonames_api'
require 'filecache'

$html_root="."
GeoNamesAPI.username = 'brianegge'
GeoNamesAPI.lang = 'e:en'
$geocache = FileCache.new(domain='intersections', root_dir='data/cache')
$reversecache = FileCache.new(domain='reverse', root_dir='data/cache')

def getNear(lat,lon)
  key = [lat,lon]
  v = $geocache.get(key)
  if not v.nil? then
    return v
  end
  begin
    near = GeoNamesAPI::NearestIntersection.find(@lat,@lon)
    sleep 0.2
    if not near.intersection.nil? then
      print '.'
      v = near.intersection['street1'] + " and " + near.intersection['street2']
      $geocache.set(key,v)
      return v
    else
      print '*'
    end
  rescue NoMethodError
    print 'M'
  rescue OpenURI::HTTPError
    print 'X'
  end
  return @street
end

class Address
  attr_reader :type, :id, :lat, :lon, :name, :leisure, :attraction, :access
  def initialize(xml)
    @xml = xml
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
    @access = get('access')
    @attraction = get('actraction')
    @beers = get('brewery')
    @cuisine = get('cuisine')
    @description = (get('description') or get('note'))
    @housenumber = get('addr:housenumber')
    @leisure = get('leisure')
    @name = get('name')
    @opening_hours = get('opening_hours')
    @phone = (get('phone') or get( 'contact:phone'))
    @street = get('addr:street')
    @website = (get('website') or get('contact:website'))
    @wikipedia = get('wikipedia')
    @near = nil
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
    score += 20 if get('image')
    score
  end
  def get(key)
    node = @xml.at_xpath("tag[@k='#{key}']")
    if node then
      return node.attr('v')
    end
    return nil
  end
  def bitcoin?
    get('payment:bitcoin') == 'yes'
  end
  def organic?
    get('organic') == 'yes'
  end
  def wifi?
    get('internet_access') =~ /yes|wlan/
  end
  def wheelchair?
    get('wheelchair') == 'yes'
  end
  def nearest_intersection
    begin
      if @near.nil? then
        @near = GeoNamesAPI::NearestIntersection.find(@lat,@lon)
        sleep 1.8
      end
      if not @near.intersection.nil? then
        print '.'
        return @near.intersection['street1'] + " and " + @near.intersection['street2']
      else
        print '*'
      end
    rescue OpenURI::HTTPError
      print 'X'
    end
    $stdout.flush
    nil
  end
  def getAddress
    #url="http://nominatim.openstreetmap.org/reverse?osm_type=#{@type.upcase[0]}&osm_id=#{@id}&format=json&email=#{EMAIL}"
    url="http://open.mapquestapi.com/nominatim/v1/reverse.php?osm_type=#{@type.upcase[0]}&osm_id=#{@id}&format=json&email=#{EMAIL}"
    json = $reversecache.get(url)
    if json.nil? then
      json = JSON.load(open(url))
      if json['error'] then
        puts url
        puts JSON.pretty_generate(json)
        return nil
      else
        $reversecache.set(url,json)
      end
    end
    @housenumber = json['address']['house_number']
    @street = json['address']['road']
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
      "#{cuisine.gsub(/_/, ' ').capitalize}"
    else
      nil
    end
  end
  def image
    i = get('image')
    if i then
      # http://commons.wikimedia.org/wiki/File:AldrichMuseumExterior.jpg
      if %r{http[s]?://commons.wikimedia.org/wiki/File:(?<name>[^#]*)} =~ i then
        url = "http://commons.wikimedia.org/w/api.php?action=query&titles=File:#{name}&prop=imageinfo&iilimit=1&iiprop=url&iiurlwidth=128&iiurlheight=128&format=xml&continue="
        xml = Nokogiri.XML(open(url))
        thumburl = xml.at_xpath('//imageinfo/ii/@thumburl').value
        thumbwidth = xml.at_xpath('//imageinfo/ii/@thumbwidth').value
        thumbheight = xml.at_xpath('//imageinfo/ii/@thumbheight').value
        descriptionurl = xml.at_xpath('//imageinfo/ii/@descriptionurl').value
        return "<a href=\"#{descriptionurl}\" target=\"wikimedia\"><img style=\"float: left; margin: 5px;\" src=\"#{thumburl}\" width=\"#{thumbwidth}\" height=\"#{thumbheight}\" alt=\"Wikimedia Commons image of #{name}\" /></a>"
      else
        $stderr.puts "Failed to parse image #{i} #{@edit}"
      end
    else
      nil
    end
  end
  def html
    o = "<div class=\"entry\"><p>"
    i = image
    if i then
      o += i
    end
    o += "<a href=\"#{@view}\" title=\"View #{@name} on OpenStreetMap.org\" target=\"osm\"><strong>#{@name}</strong></a>"
    if get('alt_name') then
      o += " <i>(" + get('alt_name') + ")</i>"
    end
    o += "<br />\n"
    if detail then
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
    if @housenumber.nil? then
      getAddress
    end
    if @housenumber and @street then
      o += "#{@housenumber} #{@street}<br />\n"
    else
      n = getNear(@lat,@lon)
      o += "#{n}<br />\n" if not n.nil?
    end
    if @phone then
      o += "<a href=\"tel:#{@phone}\">#{@phone}</a><br />\n"
    end
    if @website then
      begin
        if @website =~ /^www./ then
          uri = URI('http://' + @website)
        else
          uri = URI(@website)
        end
        if uri.scheme.nil? then
          $stderr.puts "URL missing scheme: #{@website} #{@edit}"
          @website = "http://#{@website}"
          uri = URI(@website)
        end
        if uri.host then
          o += "<a href=\"#{uri}\">#{uri.host.gsub(/^www./,'')}</a>&nbsp;"
        else
          $stderr.puts "Invalid URL: #{@website} #{@edit}"
        end
      rescue URI::InvalidURIError
        $stderr.puts "Invalid URL: #{@website} #{@edit}"
      end
    end
    if @opening_hours then
      o += "Open #{@opening_hours}&nbsp;&nbsp;"
    end
    if organic? then
      o += "<img src=\"#{$html_root}/images/organic16.png\" alt=\"Organic\" />&nbsp;"
    end
    if wifi? then
      o += "<img src=\"#{$html_root}/images/wifi16.png\" alt=\"Free Wifi\">\&nbsp;"
    end
    if bitcoin? then
      o += "<img src=\"#{$html_root}/images/bitcoin16.png\" alt=\"Merchant accepts Bitcoin payments\">\&nbsp;"
    end
    if wheelchair? then
      o += "<img src=\"#{$html_root}/maki/disability-18.png\" alt=\"Handicap accessable\">&nbsp;"
    end
    if @wikipedia then
      w=@wikipedia.split(':')
      o += "<a href=\"http://#{w[0]}.wikipedia.org/wiki/#{w[1].gsub(/_/,' ')}\" target=\"wikipedia\"><img src=\"#{$html_root}/images/wikipedia16.png\" alt=\"#{@name} on Wikipedia\"></a>&nbsp;"
    end
    o += '</p><hr /></div>'
    o
  end
  def sortkey
    @name.downcase.gsub(/^the /,'')
  end
  def ==(other)
    self.type == other.type and self.id == other.id
  end
end

class Cafe < Address
  def initialize(xml)
    super(xml)
  end
  def detail
    nil
  end
end

class Church < Address
  attr_reader :religion, :denomination
  def initialize(xml)
    super(xml)
    @religion = get('religion')
    if @religion then
      @religion.capitalize!
    end
    @denomination = get('denomination')
    if @denomination then
      @denomination.gsub!(/_/,' ')
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

def render_city(city_dir, city, state, place, root)
  $html_root=root
  dining = parse(File.join(city_dir,'dining.xml'), Address)
  cafes = parse(File.join(city_dir,'cafes.xml'), Cafe)
  icecream = parse(File.join(city_dir,'icecream.xml'), Address)
  cafes.delete_if {|v| icecream.include?(v) }

  entertainment = parse(File.join(city_dir,'entertainment.xml'), Address)
  arts = parse(File.join(city_dir,'arts.xml'), Address)
  leisure = parse(File.join(city_dir,'leisure.xml'), Address)
  golf = []
  leisure.delete_if {|v| golf << v if v.leisure == 'golf_course'}
  playgrounds = []
  leisure.delete_if {|v| playgrounds << v if v.leisure == 'playground'}
  leisure.delete_if {|v| v.type == 'node'}
  leisure.delete_if {|v| v.attraction == 'animal'}
  leisure.delete_if {|v| v.access == 'private'}
  leisure.delete_if {|v| ['stadium','sports_centre','pitch'].member?(v.leisure)}

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

def render_state(state, state_html, places, empty_cities, root)
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
