#!/usr/bin/ruby1.9.1 --disable-gems

class OsmBase
  def initialize(xml)
    @xml = xml
  end
  def osm_id
    @xml.attr('id')
  end
  def osm_type
    @xml.name
  end
  def edit
    "http://www.openstreetmap.org/edit?editor=id&#{self.osm_type}=#{self.osm_id}#map=18/#{@lat}/#{@lon}"
  end
  def view
    "http://www.openstreetmap.org/#{self.osm_type}/#{self.osm_id}"
  end
end
