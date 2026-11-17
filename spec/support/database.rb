# frozen_string_literal: true

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :products do |t|
    t.string :type
    t.string :name
    t.string :slug
    t.integer :price
    t.timestamps
  end

  create_table :variants do |t|
    t.references :product
    t.integer :price
    t.timestamps
  end

  create_table :reviews do |t|
    t.references :product
    t.boolean :published, default: false, null: false
    t.timestamps
  end
end

class TestRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Product < TestRecord
  has_many :variants
  has_many :reviews
end

class DigitalProduct < Product; end

class Variant < TestRecord
  belongs_to :product
end

class Review < TestRecord
  belongs_to :product
end
