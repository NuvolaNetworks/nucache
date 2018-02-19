require "nucache/version"

module Nucache
  class Config
    @@cache_invalidation_timeout = 24.hours.ago
    @@using_sidekiq = false
    def self.get_invalidation_timeout
      return @@cache_invalidation_timeout
    end
    def self.sidekiq?
      return @@using_sidekiq
    end
  end
  module CountMonkeyPatch
    def count(column_name=nil, nocache=false, invalidation=nil)
      return super(column_name) if nocache
      return super(column_name) if group_values.any?
      amber = "CachingTable".constantize rescue nil
      if amber.nil?
        throw Exception.new("Missing Class CachingTable")
        return
      end
      invalidation_date = invalidation
      if invalidation_date.nil?
        if !(defined? self.count_cache_invalidation).nil?
          invalidation_date = self.count_cache_invalidation
        end
      end
      if invalidation_date.nil?
        invalidation_date = Nucache::Config.get_invalidation_timeout
      end
      sql = self.to_sql
      nucache = CachingTable.where("md5(sql)::uuid = md5(?)::uuid", sql).where("updated_at > ?", invalidation_date).pluck(:count)
      count = 0
      if nucache.blank?
        count = super(column_name)
        nucache_expired = CachingTable.where("md5(sql)::uuid = md5(?)::uuid", sql).first
        if nucache_expired.nil?
        CachingTable.create(sql: sql, count: count)
        else
          nucache_expired.update(count:count,updated_at:Time.now)
        end
      else
        count = nucache[0]
      end
      return count
    end
  end
end
ActiveRecord::Calculations.prepend Nucache::CountMonkeyPatch
