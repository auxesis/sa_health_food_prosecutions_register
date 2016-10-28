require 'scraperwiki'
require 'nokogiri'
require 'mechanize'
require 'geokit'
require 'pry'
require 'active_support'
require 'active_support/core_ext'

# Set an API key if provided
Geokit::Geocoders::GoogleGeocoder.api_key = ENV['MORPH_GOOGLE_API_KEY'] if ENV['MORPH_GOOGLE_API_KEY']

def scrub(text)
  text.gsub!(/[[:space:]]/, ' ') # convert all utf whitespace to simple space
  text.strip
end

def get(url)
  @agent ||= Mechanize.new
#  @agent.user_agent_alias = 'Windows Firefox'
  page = @agent.get(url)
  p page.class
  p page.header
  puts page.content
  page
end

get('http://l.fractio.nl/request_from_morph')

# This attemps to solve a complicated problem where the information is spread
# across multiple elements. This finds all the elements until the next "header"
# (a strong element), then converts them all to text.
def extract_multiline(name, page, opts={})
  options = { :scrub => false }.merge(opts)
  start_el = page.find {|e| e.text =~ /#{name}/i}
  els = [start_el]
  current = start_el.next
  until current.children.find {|c| c.name == 'strong'} do
    els << current
    current = current.next
  end
  text = els.map(&:text).join
  standalone = text[/#{name}\**:[[:space:]](.*)/im, 1]
  options[:scrub] ? scrub(standalone) : standalone.strip
end

def extract_attrs(page)
  attrs = {}

  # Address of business
  attrs['address'] = extract_multiline('address of business', page)
  return nil if attrs['address'].blank?

  # Trading name
  text = page.find {|e| e.text =~ /trading name/i}.text
  attrs['trading_name'] = text[/^trading name\*:.(.*)/i, 1]

  # Name of convicted
  attrs['name_of_convicted'] = extract_multiline('name of convicted', page)

  # Date of offence
  attrs['date_of_offence'] = extract_multiline('date of offence', page)

  # Nature and circumstances of offence
  attrs['offence_nature'] = extract_multiline('nature and circumstances of offence', page)

  # Court decision date
  text = page.find {|e| e.text =~ /court decision date/i}.text
  attrs['court_decision_date'] = text[/^court decision date:.(.*)/i, 1]

  # Court
  text = page.find {|e| e.text =~ /court:/i}.text
  text = scrub(text).strip
  attrs['court'] = text[/^court:.(.*)/i, 1]

  # Prosecution brought by
  text = page.find {|e| e.text =~ /prosecution brought by/i}.text
  attrs['prosecution_brought_by'] = text[/^prosecution brought by:.(.*)/i, 1]

  # Fine
  text = page.find {|e| e.text =~ /fine:/i}.text
  attrs['fine'] = text[/^(\d*\..)*fine:.(.*)/i, 2]

  # Prosecution Costs
  # Optional. Not all prosecutions have these.
  if el = page.find {|e| e.text =~ /prosecution costs:/i}
    text = el.text
    attrs['prosecution_costs'] = text[/^prosecution costs:.(.*)/i, 1]
  end

  # Victim of Crime Levy
  # 'victim' is singular and pluralised, so match on both because wtf
  text = page.find {|e| e.text =~ /victims* of crime( levy)*:*/i}.text
  attrs['victims_of_crime_levy'] = text[/^victims* of crime( levy)*:*.(.*)/i, 2]

  # Total Penalty
  text = page.find {|e| e.text =~ /total( penalty)*:/i}.text
  attrs['total_penalty'] = text[/total([[:space:]]penalty)*:[[:space:]]*(.*)/i, 2]

  # Comments
  # Optional. Not all prosecutions have these.
  if el = page.find {|e| e.text =~ /comments:/i}
    text = el.text
    attrs['comments'] = text[/^comments:.(.*)/i, 1]
  end

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
  'http://www.sahealth.sa.gov.au/wps/wcm/connect/public+content/sa+health+internet/about+us/legislation/food+legislation/food+prosecution+register'
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
  new_prosecutions.map! {|p| geocode(p) }

  # Serialise
  ScraperWiki.save_sqlite(['link'], new_prosecutions)

  puts "Done"
end

main()
