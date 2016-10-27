require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'pry'
require 'active_support'
require 'active_support/core_ext'

# Set an API key if provided
Geokit::Geocoders::GoogleGeocoder.api_key = ENV['MORPH_GOOGLE_API_KEY'] if ENV['MORPH_GOOGLE_API_KEY']

def get(url)
  @agent ||= Mechanize.new
  @agent.get(url)
end

def extract_attrs(page)
  attrs = {}

  text = page.find {|e| e.text =~ /address of business/i}.text
  attrs['address'] = text[/^address of business:.(.*)/i, 1]
  return nil if attrs['address'].blank?

  attrs
end

def extract_ids(page)
  page.search('h3 a').map {|a|
    {
      'id'   => a['id'],
      'link' => base + '#' + a['id'],
    }
  }
end

def build_prosecution(attrs, page)
  doc = Nokogiri::HTML(page.body) {|c| c.noblanks}
  elements = doc.search('div.wysiwyg').first.children
  header = elements.search("//a[@id='#{attrs['id']}']").first.parent

  els = [header]
  current = header.next
  until current.nil? || current.name == 'h3' do
    els << current
    current = current.next
  end

  if more_attrs = extract_attrs(els)
    puts "Extracting #{more_attrs['address']}"
    attrs.merge(more_attrs)
  else
    nil
  end
end

def geocode(notice)
  @addresses ||= {}

  address = notice['address']

  if @addresses[address]
    puts "Geocoding [cache hit] #{address}"
    location = @addresses[address]
  else
    puts "Geocoding #{address}"
    a = Geokit::Geocoders::GoogleGeocoder.geocode(address)
    location = {
      'lat' => a.lat,
      'lng' => a.lng,
    }

    @addresses[address] = location
  end

  notice.merge!(location)
end

def base
  "http://www.sahealth.sa.gov.au/wps/wcm/connect/public+content/sa+health+internet/about+us/legislation/food+legislation/food+prosecution+register"
end

def existing_record_ids
  return @cached if @cached
  @cached = ScraperWiki.select('link from data').map {|r| r['link']}
rescue SqliteMagic::NoSuchTable
  []
end

def main
  page = get(base)
  prosecutions = extract_ids(page)

  puts "### Found #{prosecutions.size} prosecutions"
  new_prosecutions = prosecutions.select {|r| !existing_record_ids.include?(r['link']) }
  puts "### There are #{new_prosecutions.size} new prosecutions"

  new_prosecutions.map! {|p| build_prosecution(p, page) }.compact!
  new_prosecutions.map! {|n| geocode(n) }

  # Serialise
  ScraperWiki.save_sqlite(['link'], new_prosecutions)

  puts "Done"
end

main()
