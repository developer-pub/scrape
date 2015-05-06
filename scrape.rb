require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'capybara/mechanize'
require 'pp'

require 'sqlite3'
require 'active_record'

module Scrape
  class Test
    include Capybara::DSL
    
    def load
      Capybara.current_driver = :mechanize

      Capybara.configure do |config|
        config.run_server = false
        config.default_driver = :mechanize
      end

      #The following is needed, otherwise Capybara standalone throws an error
      Capybara.app = "make sure this isn't nil"

      main_url = "http://www.flexjobs.com"

      visit(main_url + "/jobs")

      categories = []

      all(:xpath, "//*[@id='jobcateg']/div/ul[@role='tree']/li[@role='treeitem']/a[not(@class='pull-right')]").each do |category_el|
        categories << {link: category_el[:href], name: category_el.text}
      end

      #Arbitrary limit for testing
      categories = categories.first(7)

      categories.each do |category|
        puts "Getting offers of category: #{category[:link]}: #{category[:name]}"

        visit_with_pause (main_url + category[:link]) 

        category[:offers] = []

        #Also arbitrary limit just for testing
        all(:xpath, "//*[@id='joblist']/li/div/div[1]/h5/a").first(15).each do |offer_header_el|
          puts "Getting offer: #{offer_header_el.text}, link: #{offer_header_el[:href]}"

          visit_with_pause(URI.encode(main_url + offer_header_el[:href]))

          offer = {}

          offer[:link] = offer_header_el[:href]
          offer[:title] = offer_header_el.text
          offer[:description] = find(:xpath, "//*[@id='job-description'][1]//p").text

          all(:xpath, "//*[@id='job-description'][2]//tr").each do |offer_attr_el|
            name = offer_attr_el.find(:xpath, "./th").text
            value = offer_attr_el.find(:xpath, "./td").text

            case name 
            when "Date Posted:"
              offer[:date] = value
            when "Location:"
              offer[:location] = value
            when "Hours per Week:"
              offer[:hours_per_week] = value
            when "Career level:"
              offer[:career_level] = value
            when "Flexibility:"
              offer[:flexibility] = value
            end
          end

          category[:offers] << offer
        end
      end

      pp categories

      @categories = categories
    end

    def save_to_db
      ActiveRecord::Base.establish_connection :adapter => 'sqlite3', :database => 'development.sqlite3'

      clear_db

      @categories.each do |category|
        category_db = Category.create! :name => category[:name]

        category[:offers].each do |offer|
          offer_db = Offer.create!({category: category_db, title: offer[:title], body: offer[:description]})
        end
      end
    end

    private
      #Pausing, so as to not overload the server
      def visit_with_pause(link)
         sleep(2 + rand(5))
         visit link
      end

      def clear_db
        Offer.all.each do |el|
          el.destroy
        end

        Category.all.each do |el|
          el.destroy
        end
      end
  end
end

#require '../jobs/app/models/offer'
#require '../jobs/app/models/category'

#Models pasted here for simplicity of GitHub cloning, normally the above works when directories are set up properly
#Alternatively we could extract models as a gem and require that gem in both projects
class Offer < ActiveRecord::Base
  belongs_to :category
end

class Category < ActiveRecord::Base
  has_many :offers
end

scraper = Scrape::Test.new

scraper.load
scraper.save_to_db
