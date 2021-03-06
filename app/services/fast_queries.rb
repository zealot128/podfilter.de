module FastQueries
  module_function
  def episode_count
    Episode.connection.execute('SELECT reltuples FROM pg_class WHERE relname = \'episodes\'').first.values.first.to_f.to_i
  end

  # [ [Episode, Podcast], [Episode, Podcast] ...
  def recently_updated_podcasts(limit: 10, interval: 21.days)
    query = <<-SQL
    WITH episodes_per_podcast AS (
      SELECT id, podcast_id, pubdate FROM (
        SELECT episodes.id , podcast_id, episodes.pubdate, row_number() OVER (PARTITION BY podcast_id ORDER BY episodes.pubdate DESC) AS pos
        FROM "episodes"
        INNER JOIN "sources" ON "sources"."id" = "episodes"."source_id"
        WHERE episodes.pubdate > '#{interval.ago.to_date.to_s}'
      )a1 WHERE pos = 1
    )
    SELECT * FROM episodes_per_podcast
    WHERE (SELECT id FROM podcasts WHERE podcasts.id = podcast_id AND subscriber_count > 0 LIMIT 1) IS NOT NULL AND pubdate < '#{Time.now.to_s}'
    ORDER BY pubdate desc
    LIMIT #{limit};
    SQL
    result = Podcast.connection.execute(query).to_a
    episode_ids = result.map{|i| i['id']}
    podcast_ids = result.map{|i| i['podcast_id']}
    Episode.find(episode_ids).sort_by{|i| episode_ids.index(i.id.to_s)}.zip(
      Podcast.find(podcast_ids).sort_by{|i| podcast_ids.index(i.id.to_s)}
    )
  end
end
