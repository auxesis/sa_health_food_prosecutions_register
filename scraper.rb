require 'scraperwiki'
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
  @agent.get(url)
end

def extract_attrs(page)
  attrs = {}

  # Address of business
  text = page.find {|e| e.text =~ /address of business/i}.text
  attrs['address'] = text[/^address of business:.(.*)/i, 1]
  # FIXME(auxesis) needs multiline
  return nil if attrs['address'].blank?

  # Trading name
  text = page.find {|e| e.text =~ /trading name/i}.text
  attrs['trading_name'] = text[/^trading name\*:.(.*)/i, 1]

  # Name of convicted
  text = page.find {|e| e.text =~ /name of convicted/i}.text
  attrs['name_of_convicted'] = text[/^name of convicted\*:.(.*)/i, 1]
  # FIXME(auxesis) needs multiline

  # Date of offence
  text = page.find {|e| e.text =~ /date of offence/i}.text
  attrs['date_of_offence'] = text[/^date of offence:.(.*)/i, 1]

  # Nature and circumstances of offence

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
  new_prosecutions.map! {|p| geocode(p) }

  binding.pry

  exit
  # Serialise
  ScraperWiki.save_sqlite(['link'], new_prosecutions)

  puts "Done"
end

main()
