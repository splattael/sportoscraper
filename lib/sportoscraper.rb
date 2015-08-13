require 'bundler/setup'

class Sportoscraper
  require 'mechanize'
  require 'pathname'

  BASE_URL  = %{http://www.sportograf.com}
  OVERVIEW  = %{#{BASE_URL}/de/shop/event/%{event_id}}
  SEARCH    = %{#{BASE_URL}/de/shop/search/%{event_id}/t/%{tag_id}?page=%{page}}

  class Agent < Mechanize
    def initialize
      super
      self.user_agent = "Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/28.0.1500.71 Chrome/28.0.1500.71 Safari/537.36"
    end
  end

  class Overview
    def initialize(agent, event)
      @agent = agent
      @event = event
    end

    def tags
      page = @agent.get OVERVIEW % { :event_id => @event.id }
      page.search("select[id='tag_id']/option").map do |option|
        Tag.new(option['value'], option.text)
      end
    end
  end

  Event = Struct.new(:id, :name) do
    def normalized_name
      "#{id}_#{name}"
    end
  end

  Tag = Struct.new(:id, :name) do
    def normalized_name
      "#{id}_#{name}"
    end
  end

  Image = Struct.new(:id, :path, :time) do
    def normalized_name
      "#{time}_#{id}.jpg"
    end

    def url
      if path =~ /^http/
        path
      else
        "#{BASE_URL}#{path}"
      end
    end
  end

  class Storage
    require 'fileutils'

    def initialize(base_dir, event)
      @base_dir = Pathname.new(base_dir).join(event.normalized_name)
    end

    def store(tag, image, &block)
      tag_name = tag.normalized_name
      image_name = image.normalized_name

      path = @base_dir.join(tag_name).join(image_name)
      FileUtils.mkdir_p(path.dirname)
      unless path.exist?
        content = yield(path)
        puts "Saving #{content.size} bytes to #{path}"
        File.open(path, "wb") do |f|
          f.write(content)
        end
      end
    end
  end

  class Scraper
    attr_reader :next_page

    def initialize(agent, event, tag)
      @agent      = agent
      @event      = event
      @tag        = tag
      @next_page  = 1
    end

    def each(&block)
      loop do
        break unless @next_page
        images.each do |image|
          yield image
        end
      end
    end

    def images
      url = SEARCH % { :event_id => @event.id, :tag_id => @tag.id, :page => @next_page }
      puts "== URL: #{url}"
      page = @agent.get url
      determine_next_page!(page)
      page.search("div[class='m-shop-item js-popup-data']").map do |table|
        path    = table.at("a/img[class='img-responsive']")['src']
        caption = table.search("div[class='m-shop-item--caption']/strong")
        id      = caption[0].text
        time    = caption[1].text
        Image.new(id, path, time)
      end
    end

    private

    def determine_next_page!(page)
      if next_page = page.at("a[rel='next']")
        @next_page = next_page['href'][/page=(\d+)/, 1]
      else
        @next_page = nil
      end
    end
  end

  def initialize(agent, event, tag, base_dir)
    @agent    = agent
    @event    = event
    @tag      = tag
    @scraper  = Scraper.new(agent, event, tag)
    @storage  = Storage.new(base_dir, event)
  end

  def download!
    @scraper.each do |image|
      @storage.store(@tag, image) do |path|
        @agent.get_file(image.url)
      end
    end
  end
end

if $0 == __FILE__
  RAD_AM_RING = Sportoscraper::Event.new(2840, "Rad am Ring 2015")
  DIR = ARGV[0] || "/tmp/sportograf"

  agent = Sportoscraper::Agent.new

  tags = Sportoscraper::Overview.new(agent, RAD_AM_RING).tags

  tags.each do |tag|
    scraper = Sportoscraper.new(agent, RAD_AM_RING, tag, DIR)
    scraper.download!
  end
end
