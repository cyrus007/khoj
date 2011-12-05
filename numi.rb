# numi.rb
require 'rubygems' if RUBY_VERSION < '1.9'
require 'sinatra'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'data_mapper'
#require './periodic'

DataMapper.setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/numi.db')

class Banner
  include DataMapper::Resource

  property :id, Serial
  property :src, String,   :required => true
  property :title, String, :required => true
  property :url, Text,     :required => true
end
# automatically create the table
#Banner.auto_migrate! unless Banner.storage_exists?
DataMapper.auto_upgrade!

class Movies
  def initialize(filename)
    @filename = filename
  end

  def load
    parsed.map { |attributes| attributes }
  end

  def parsed
    fd = File.exists?(@filename) ? File.read(@filename) : "[]"
    JSON.parse(fd, :symbolize_names => true)
  end

# def scrape_again
#   movies = Scraper.scrape
# end
end

class Server
    def initialize(no)
      @no = no
      @parts = []
    end

    def <<(part)
      @parts << part
    end

    def serialize
      { :no => @no, :links => @parts }
    end
end

class Scraper
    def initialize
    end
end

class Rangu < Scraper
    def initialize
      @src = 'rangu'
    end

    def getLinks(page)
      doc = Nokogiri::HTML(page)
      node = doc.css('div.middle_movies > div.post > h2')
      title = node.inner_html
      node = doc.css('div.middle_movies > div.post > div')
      lines = node[1].to_s.split('<br'); line_nos = lines.length
      if lines.length < 3
        return "No servers found", 1
      else
        splice = lines[0].split('src=')[1].match(/\"([^\"]+)\"/); img = $1.to_s
        banner = Banner.first(:src => @src, :title => title) rescue nil
        cnt = 0
        begin
          splice = lines[cnt].strip; cnt += 1
        end while !splice.include? "Online"
        output = extract(lines, cnt)

        banner ||= Banner.create(:src => @src, :title => title, :url => img) unless img.empty? || title.empty?  #same as new + save
        result = { :title => title, :img => img, :servers => output }
        return result, 0
      end
    end

    def extract(lines, i)
          serialized = []; serv_nos = 1
          while i < lines.length
            splice = lines[i].strip;
            if splice.include? "Server"
              s = Server.new(serv_nos); serv_nos += 1
              i += 1; server = lines[i].strip
              links = server.split('</a>'); link_nos = links.length
              j = 0
              while j < links.length
                links[j].match(/href=\"([^&]+)&/); link = $1.to_s
                links[j].match(/href=\"([^\"]+)\"/) && link = $1.to_s if link.empty? 
                s << link unless (link.nil? || link.empty?)
                j += 1
              end
              serialized << s.serialize
              i += 1
            else
              if serialized.length == 0
                s = Server.new(serv_nos); serv_nos += 1
                server = lines[i].strip
                links = server.split('</a>'); link_nos = links.length
                j = 0
                while j < links.length
                  links[j].match(/href=\"([^&]+)&/); link = $1.to_s
                  links[j].match(/href=\"([^\"]+)\"/) && link = $1.to_s if link.empty? 
                  s << link unless (link.nil? || link.empty?)
                  j += 1
                end
                serialized << s.serialize
              end
              i += 1   #needed for both when serialized.length >= 0
            end
          end
        return serialized
    end
end

before do
    cache_control :public, :must_revalidate, :max_age => 600
end

get '/' do
    redirect '/index.html'
end

get '/:src/search' do |src|
    halt(404, 'Not implemented') if src != 'rangu' or src.empty?
    t = params[:str] if params[:str]
    halt(404, 'No search string given') if t.nil? || t.empty?

    title_re = Regexp.new(t, Regexp::IGNORECASE)
    if src == 'rangu'
      dbfile = 'rangu-db.json'
    elsif src == 'stt'
      dbfile = 'stt-db.json'
    elsif src == 'bm'
      dbfile = 'bm-db.json'
    else
      halt(404, 'Should not have reached here.')
    end
    dbrows = Movies.new(dbfile).load
    result = []
    dbrows.each do |i|
      next i unless i[:title] && i[:title] =~ title_re
      banner = Banner.first(:src => src, :title => i[:title]) rescue nil
      result << { :title => i[:title], :img => banner ? banner.url : '', :url => i[:url] }
    end
    result.to_json
end

get '/:src/getvids' do |src|
    halt(404, 'Not implemented') if src != 'rangu' or src.empty?
    url = URI.escape(params[:url])
    halt(404, 'Empty URL') if url.empty?

#    ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')    #fix encoding errors
#    response = ic.conv(open(url).read)
#    response = AppEngine::URLFetch.fetch(url).body.gsub!(/[\n\r]/, "")
    response = open(url).read
    if src == 'rangu'
      rangu = Rangu.new
    elsif src == 'stt'
    elsif src == 'bm'
    else
      halt(404, 'Should not have reached here.')
    end
    result, errcode = rangu.getLinks(response)
    if errcode > 0
      return result
    else
      result.to_json
    end
end
