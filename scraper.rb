# encoding: utf-8
require 'mechanize'
require 'sqlite3'

def create_tables(db)
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS keywords (
      keyword_text TEXT PRIMARY KEY,
      keyword_link TEXT,
      kategorie_id INTEGER
    );
  SQL

  db.execute "DROP TABLE IF EXISTS companies"

  db.execute <<-SQL
    CREATE TABLE companies (
      name TEXT,
      street_name TEXT,
      house_number TEXT,
      zip_code TEXT,
      city TEXT,
      phone TEXT,
      fax TEXT,
      email TEXT,
      website TEXT,
      additional_info TEXT,
      keyword_text TEXT,
      kategorie_id INTEGER,
      mandat_id INTEGER,
      PRIMARY KEY (name, mandat_id)
    );
  SQL
end

def extract_company_links(page)
  company_links = []

  # Find the highlighted company link
  highlighted_link = page.at('article.contrast_border h4 a')
  company_links << highlighted_link if highlighted_link

  # Find the regular company links
  regular_links = page.search('div[id^="mandat_"] a')
  company_links.concat(regular_links)

  company_links
end

def extract_company_data(page, keyword_text, kategorie_id, mandat_id)
  name_element = page.at('h1')
  name = name_element ? name_element.text.strip : nil

  address_element = page.at('article.contrast_border p, p:contains("Schenefeld")')
  if address_element
    address_text = address_element.text.strip
    address_parts = address_text.split(/(\d{5})/).map(&:strip)
    if address_parts.length >= 3
      street_and_number = address_parts[0].split(/(\d+\s*-\s*\d+|\d+\s*\w?)/).map(&:strip).reject(&:empty?)
      street_name = street_and_number[0..-2].join(' ')
      house_number = street_and_number[-1]
      zip_code = address_parts[1]
      city = address_parts[2]
    else
      street_name = nil
      house_number = nil
      zip_code = nil
      city = nil
    end
  else
    street_name = nil
    house_number = nil
    zip_code = nil
    city = nil
  end

  # ... (rest of the method remains the same)
end

db = SQLite3::Database.new('data.sqlite')
create_tables(db)

agent = Mechanize.new
base_url = 'https://www.stadt-schenefeld-wirtschaft.de'

('A'..'Z').each do |letter|
  puts "Scraping letter: #{letter}"

  keyword_url = "#{base_url}/verzeichnis/index.php?verzeichnistyp=0&buchstabe=#{letter}"
  keyword_page = agent.get(keyword_url)

  keywords = keyword_page.search('div[style="width:100%;margin-top:0;"] a')
  puts "Found #{keywords.count} keywords for letter #{letter}"

  keywords.each_with_index do |keyword, index|
    keyword_text = keyword.text.strip
    keyword_link = keyword['href']
    kategorie_id = keyword_link.match(/kategorie=(\d+)/)[1]

    puts "Keyword #{index + 1}: #{keyword_text} (Kategorie ID: #{kategorie_id})"

    begin
      db.execute("INSERT OR REPLACE INTO keywords (keyword_text, keyword_link, kategorie_id) VALUES (?, ?, ?)", [keyword_text, "#{base_url}#{keyword_link}", kategorie_id])
      puts "Keyword data saved to the database."
    rescue SQLite3::Exception => e
      puts "Error saving keyword data to the database: #{e.message}"
    end

    keyword_page = agent.get(keyword_link)

    company_links = extract_company_links(keyword_page)
    puts "Found #{company_links.count} companies for keyword #{keyword_text}"

    company_links.each_with_index do |company_link, company_index|
      company_url = "#{base_url}#{company_link['href']}"
      mandat_id = company_link['href'].match(/mandat=(\d+)/)[1]

      puts "Company #{company_index + 1}: #{company_link.text.strip} (Mandat ID: #{mandat_id})"

      company_page = agent.get(company_url)
      extract_company_data(company_page, keyword_text, kategorie_id, mandat_id)
    end
  end
end

db.close
