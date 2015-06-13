require 'file_mime_type_validator'
class Source < ActiveRecord::Base
  include PgSearch
  pg_search_scope :search,
    :against => [:title, :description, :url],
    :using => {
      :tsearch => {:prefix => true}
    }

  # has_ancestry
  has_many :opml_files_sources
  has_many :opml_files, through: :opml_files_sources
  has_many :owners, through: :opml_files
  has_many :episodes, dependent: :destroy
  mount_uploader :image, ImageUploader
  belongs_to :podcast
  belongs_to :redirected_to, class_name: 'Source'
  has_many :redirected_from, class_name: 'Source', foreign_key: 'redirected_to_id'

  after_destroy do
    if self.podcast.sources.blank?
      self.podcast.destroy
    end
  end
  after_save do
    podcast.try(:set_subscriber_count!)
  end

  def self.active
    source_id = Episode.connection.execute(
      Episode.select('distinct source_id').
      where('pubdate > ?', 1.year.ago).to_sql
    ).to_a.map{|i| i['source_id']}
    where(id: source_id)
  end


  validates :url, presence: true, uniqueness: { :case_sensitive => false }, url: true, if: ->(r) { !Rails.env.test?}
  # validates :image,
  #   :file_mime_type => {
  #   :content_type => /image/
  # }, if: ->(r) { r.image.present? and r.image_changed? }

  scope :recent, -> {
    active.
    listened.
    joins(:episodes).
    where('episodes.id = (select episodes.id from episodes where episodes.source_id = sources.id and pubdate is not null order by pubdate desc limit 1)').
    select('sources.*, episodes.id as episode_id, episodes.pubdate as pubdate').
    where('episodes.pubdate < ?', Time.zone.now).
    order('episodes.pubdate desc')
  }
  scope :error, -> { where(offline: nil) }
  scope :offline,-> { where(offline: true) }
  scope :active, -> { where(active: true).not_redirected }
  scope :not_redirected, -> { where('redirected_to_id is null') }
  scope :inactive, -> { where(active: false) }
  scope :listened, -> { where('owners_count > 0')}
  scope :popular, -> { order('owners_count desc') }
  scope :without_media_live, -> { where('(select id from episodes where source_id = sources.id and media_url is null limit 1) is not null') }
  scope :with_media_live,    -> { where('(select id from episodes where source_id = sources.id and media_url is not null limit 1) is not null') }

  scope :inactive_live, -> { where(id: Episode.select('source_id').having('max(pubdate) <= ?', 1.year.ago).group(:source_id)) }
  scope :active_live,   -> { where(id: Episode.select('distinct source_id').where('pubdate > ?', 1.year.ago)) }

  def self.update_active_status
    active_live.update_all active: true
    inactive_live.update_all active: false
    without_media_live.update_all has_media: false
    with_media_live.update_all has_media: true
  end

  def self.merge_sources(sources)
    if sources.count < 2
      raise ArgumentError
    end
    parent = sources.shift
    parent.parent = nil
    parent.save validate: false

    sources.each do |s|
      s.parent = parent
      s.save validate: false
    end
  end

  def full_refresh
    if parsed_feed.is_a?(Fixnum) or (parsed_feed.title.blank? and parsed_feed.entries.count == 0)
      self.update_column :offline, true
    else
      fetch_meta_information
      check_redirect
      if !redirected
        update_entries
      end
    end
  end

  def self.enqueue
    pluck(:id).each do |id|
      SourceUpdateWorker.perform_async(id)
    end
  end

  def check_redirect
    if url != parsed_feed.feed_url
      parent = Source.where(url: parsed_feed.url).first_or_initialize
      parent.podcast ||= self.podcast
      parent.save!
      self.opml_files.each do |oml|
        parent.opml_files << oml unless parent.opml_files.include?(oml)
      end
      self.opml_files = []
      self.redirected_to = parent
      self.save!
    else
      self.update_column :redirected_to_id, nil
    end
  end

  def fetch_meta_information
    self.podcast ||= Podcast.where(title: parsed_feed.title).first_or_initialize
    self.podcast.update_meta_information(parsed_feed)
    self.update_column :offline, false
    self.format = parsed_feed.try(:entries).try(:first).try(:enclosure_type) || 'audio/mp3'
    self.save!
  end

  def badges
    b = []
    if active? and !offline?
      b << :active
    elsif active == false and !offline?
      b << :inactive
    else
      b << :offline
    end
    if has_media
      b << :has_media
    else
      b << :has_no_media
    end
    b
  end

  def parsed_feed
    @parse_feed ||= Feedjira::Feed.fetch_and_parse(url, max_redirects: 5, timeout: 30)
  end

  def update_entries
    parsed_feed.entries.each do |entry|
      guid = entry.respond_to?(:entry_id) ? entry.entry_id : entry.guid
      if guid.blank?
        guid = entry.published && entry.published.to_s
      end
      next if guid.blank?

      episode = episodes.where(guid: guid.slice(0,255)).first_or_initialize
      episode.title = entry.title.try(:slice, 0, 255)
      episode.url   = entry.url.try(:slice, 0, 255)
      episode.description = entry.summary
      episode.pubdate = entry.published

      episode.media_url = entry.enclosure_url
      episode.save
    end
  end

  def all_siblings
    root.subtree
  end
end
