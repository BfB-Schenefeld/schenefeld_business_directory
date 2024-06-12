# encoding: utf-8
require 'mechanize'
require 'sqlite3'

def extract_company_data(page, keyword_text, kategorie_id, mandat_id = nil)
  db = SQLite3::Database.new('data.sqlite')
  begin
    name_element = page.at('h1')
    name = name_element ? name_element.text.strip : nil

    address_element = page.at('h4')
    if address_element
      address_parts = address_element.text.strip.split('<br>')
      street_address = address_parts[0].strip
      zip_city = address_parts[1].strip
      zip_code, city = zip_city.split(' ', 2)
    else
      street_address = nil
      zip_code = nil
      city = nil
    end

    phone_link = page.at('a[href^="tel:"]')
    phone = phone_link ? phone_link.text.strip : nil

    fax_link = page.at('a[aria-label^="Telefax:"]')
    fax = fax_link ? fax_link.text.strip : nil

    email_link = page.at('a[href^="mailto:"]')
    email = email_link ? email_link.text.strip : nil

    website_link = page.at('a[onclick="target=\'_blank\'"]')
    website = website_link ? website_link.text.strip : nil

    additional_info = page.search('div[style="margin-top:15px;"]').map(&:text).join("\n").strip.split("Weitere Informationen:").first.strip

    # Extract mobile phone number from additional info if available
    mobile_phone = additional_info.scan(/01\d{2}\s?\d{2}\s?\d{2}\s?\d{2}\s?\d{2}/).first

    puts "      Company: #{name}"
    puts "        Street Address: #{street_address}"
    puts "        ZIP Code: #{zip_code}"
    puts "        City: #{city}"
    puts "        Phone: #{phone}"
    puts "        Fax: #{fax}"
    puts "        Email: #{email}"
    puts "        Website: #{website}"
    puts "        Additional Info: #{additional_info}"
    puts "        Mobile Phone: #{mobile_phone}"

    # Save the extracted company data to the SQLite database
    db.execute("INSERT OR REPLACE INTO companies (name, street_address, zip_code, city, phone, fax, email, website, additional_info, mobile_phone, keyword_text, kategorie_id, mandat_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [name, street_address, zip_code, city, phone, fax, email, website, additional_info, mobile_phone, keyword_text, kategorie_id, mandat_id])
  rescue => e
    puts "Error extracting company data: #{e.message}"
    puts "Company page URL: #{page.uri}"
  ensure
    db.close if db
  end
end

agent = Mechanize.new

base_url = 'https://www.stadt-schenefeld-wirtschaft.de/verzeichnis/index.php'

# Iterate through each letter from A to Z
('A'..'Z').each do |letter|
  url = "#{base_url}?verzeichnistyp=0&buchstabe=#{letter}"
  puts "Scraping letter: #{letter}"
  page = agent.get(url)

  # Find all keywords on the current page
  keywords = page.search('div[style="width:100%;margin-top:0;"] a')
  puts "  Found #{keywords.count} keywords for letter #{letter}"

  keywords.each_with_index do |keyword, index|
    keyword_text = keyword.text.strip
    keyword_link = keyword['href']
    kategorie_id = keyword_link.match(/kategorie=(\d+)/)[1]

    puts "  Keyword #{index + 1}: #{keyword_text} (Kategorie ID: #{kategorie_id})"

    # Save the keyword and its link to the SQLite database
    keyword_url = "#{base_url}#{keyword_link}"
    db = SQLite3::Database.new('data.sqlite')
    db.execute("INSERT OR REPLACE INTO keywords (keyword_text, keyword_link, kategorie_id) VALUES (?, ?, ?)", [keyword_text, keyword_url, kategorie_id])
    db.close

    # Navigate to the keyword-listing page
    keyword_page = agent.get(keyword_link)

    # Check if the keyword-listing page has multiple companies
    if keyword_page.uri.to_s.include?('visitenkarte.php')
      # Single company, extract company data directly
      puts "    Single company found. Extracting data."
      extract_company_data(keyword_page, keyword_text, kategorie_id)
    else
      # Multiple companies, find all company links on the keyword-listing page
      company_links = keyword_page.search('a.titel')
      puts "    Found #{company_links.count} companies for keyword #{keyword_text}"

      company_links.each_with_index do |company_link, company_index|
        company_url = company_link['href']
        mandat_id = company_url.match(/mandat=(\d+)/)[1]

        puts "    Company #{company_index + 1}: Mandat ID: #{mandat_id}"

        # Navigate to the company page
        company_page = agent.get(company_url)

        # Extract company data from the company page
        extract_company_data(company_page, keyword_text, kategorie_id, mandat_id)
      end
    end
  end
end
