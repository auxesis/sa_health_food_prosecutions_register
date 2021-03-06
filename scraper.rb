# Usage: bundle exec ruby scraper.rb
#
# Environment variables:
#
#  - MORPH_GOOGLE_API_KEY: Google Maps API key
#  - MORPH_PROXY: proxy to make requests through, in the format of 'HOST:PORT'

require 'scraperwiki'
require 'nokogiri'
require 'mechanize'
require 'geokit'
require 'pry'
require 'active_support'
require 'active_support/core_ext'
require 'reverse_markdown'

# Set an API key if provided
Geokit::Geocoders::GoogleGeocoder.api_key = ENV['MORPH_GOOGLE_API_KEY'] if ENV['MORPH_GOOGLE_API_KEY']

def scrub(text)
  text.gsub!(/[[:space:]]/, ' ') # convert all utf whitespace to simple space
  text.strip
end

def get(url)
  @agent ||= Mechanize.new
  @agent.user_agent_alias = 'Windows Firefox'
  if ENV['MORPH_PROXY']
    host, port = ENV['MORPH_PROXY'].split(':')
    @agent.set_proxy host, port
    puts "Using proxy for request to #{url}"
  end
  @agent.open_timeout = 60
  @agent.read_timeout = 60

  retry_count = 0
  begin
    page = @agent.get(url)
  rescue => e
    puts "Error when fetching #{url}: #{e}"
    if (retry_count += 1) < 10
      puts "Retrying"
      retry
    else
      puts "Failed too many times. Exiting."
      exit 1
    end
  end

  page
end

# This attemps to solve a complicated problem where the information is spread
# across multiple elements. This finds all the elements until the next "header"
# (a strong element), then converts them all to text.
def extract_multiline(name, page, opts={})
  options = { :scrub => false, :markdown => false }.merge(opts)
  start_el = page.find {|e| e.text =~ /#{name}/i}
  els = [start_el]
  current = start_el.next
  until current.children.find {|c| c.name == 'strong'} do
    els << current
    current = current.next
  end
  if options[:markdown]
    html = els[1..-1].map(&:to_s).join
    ReverseMarkdown.convert(html)
  else
    text = els.map(&:text).join
    standalone = text[/#{name}\**:[[:space:]](.*)/im, 1]
    options[:scrub] ? scrub(standalone) : standalone.strip
  end
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
  attrs['offence_nature'] = extract_multiline('nature and circumstances of offence', page, :markdown => true)

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
  # 'victim' is singular, pluralised, and abbreviate, so match on all because wtf
  text = page.find {|e| e.text =~ /vic(tims*)* of crime( levy)*:*/i}.text
  attrs['victims_of_crime_levy'] = text[/^vic(tims*)* of crime( levy)*:*.(.*)/i, 2]

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

# The prosecutions are published in a big WYSIWYG text field.
# There are no <div> tags to separate each prosecution.
# This makes scraping prosecutions hard, because where do they start and end?
#
# This method:
#
# 1. Finds the header element for the offence, i.e. `#Moo View Dairy`'s parent
# 2. Find to the next element, and
# 2.1 If it's not a header node, add it to the collection
# 2.2 If it's a header node, stop
#
# This gives us a nice chunk of HTML that represents the prosecution in
# isolation from the other prosecutions.
#
# Then build_prosecution tries to extract any attributes it can from the HTML.
#
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
