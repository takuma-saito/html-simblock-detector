require 'nokogiri'
require "open-uri"
require 'kconv'
require 'pp'
require 'ap'

def remove_elem(doc)
  ['comment()',
   'script',
   'noscript',
   'style',
   'select',
   'meta',
   'link',
   'button',
   'form',
   'input',
   'option'].each do |elem|
    doc.xpath("//#{elem}").remove
  end
end

def get_xpath(doc)
  doc
end

def inner_product(x, y)
  x.map do |k, v|
    (y.key?(k)) ? (y[k] * v) : 0
  end.reduce(&:+)
end

def normalize(vec)
  sum = Math.sqrt(
    [vec.values, vec.values].transpose.map {|val| val.reduce(&:*)}.reduce(&:+))
  vec.map do |k, v|
    [k, v.to_f / sum.to_f]
  end.to_h
end

def calc_avg_size(vecs)
  return 0.0 if vecs.size <= 1
  vecs.map {|vec| vec.values.reduce(&:+)}.reduce(&:+).to_f / vecs.size.to_f
end

def calc_count_numeric(vecs)
  vecs.map {|vec| vec[:type_numeric] || 0}.reduce(&:+).to_f
end

def calc_avg_sim(vecs)
  return 0.0 if vecs.size <= 1
  vecs_norm = vecs.map {|vec| normalize(vec)}
  val = vecs_norm.map.with_index { |x, i|
    vecs_norm.map.with_index {|y, j|
      i != j ? inner_product(x, y) : 0}.reduce(&:+) }.reduce(&:+)
  return val.to_f / vecs_norm.size
end

def val_elem(doc)
  res = {}
  res[doc.name] = 1
  doc.attributes.each do |k, v|
    if k == 'class' or k == 'id'
      v.value.split(" ").each do |n|
        res["#{doc.name}_#{k}_#{n}"] = 1
      end
    end
  end
  res
end

def val(doc)
  case doc
  when Nokogiri::XML::Text
    if doc.content.strip.match /\A[-+]?[0-9]*\.?[0-9]+\Z/
      num = doc.parent.name == "a" ? 8 : 1
      {type_numeric: num}
    else
      nil
    end
  when Nokogiri::XML::ProcessingInstruction
    nil
  when Nokogiri::XML::NodeSet
    nil # skip
  when Nokogiri::XML::DTD
    nil # skip
  when Nokogiri::HTML::Document
    nil # skip
  when Nokogiri::XML::Element
    return nil if doc.name == "br"
    val_elem(doc)
  else
    raise "unknown attributes: #{doc.class}"
  end
end

def merge!(vecs, x)
  x.each do |k, v|
    if vecs.key? k
      vecs[k] += v
    else
      vecs[k] = v
    end
  end
  vecs
end

def merge_hash(vecs)
  vecs.reduce {|accum, x| merge!(accum, x) unless x.nil?}
end

def debug(&block)
  block.call unless $debug.nil?
end

def gamma_basic(x, k, theta)
  ((x ** (k - 1)) * Math.exp(- (x / theta))) / ((1...k).to_a.reduce(&:*) * (theta ** k))
end

def gamma_log(x)
  k = (AVG_SIZE / 4.0).to_i
  Math.log(gamma_basic(x, k, 4.0)) * DELTA
end

def sim_blocks(doc)
  def dfs(doc, blocks)
    children = doc&.children
    return val(doc) if children.empty?
    vecs = children.map do |elem|
      dfs(elem, blocks)
    end
    vecs = vecs.reject(&:nil?)
    avg_size = calc_avg_size(vecs)
    avg_sim = calc_avg_sim(vecs)
    path = doc.kind_of?(Nokogiri::XML::NodeSet) ? '/' : doc.path
    blocks << {
      path: path,
      score: avg_sim + gamma_log(avg_size),
      avg_size: avg_size,
      avg_sim: avg_sim,
      count_numeric: calc_count_numeric(vecs),
      doc: doc}
    hash = merge_hash(val(doc).nil? ? vecs : [val(doc)] + vecs)
    return hash
  end
  blocks = []
  dfs(doc, blocks)
  blocks
end

def sort_by_score(blocks, limit)
  blocks.sort_by {|block| block[:score]}.reverse.slice(0, limit).reverse
end

def sort_by_count_numeric(blocks, limit)
  blocks.select {|block|
    block[:avg_size] > 0
  }.sort_by {|block|
    block[:count_numeric] / block[:avg_size]
  }.reverse.slice(0, limit).reverse
end

def get_doc(html)
  doc = Nokogiri::HTML html
  remove_elem(doc)
  doc
end

def reject_by_sim_ratio(blocks, ratio = 10.0)
  blocks.reject {|block| (block[:avg_sim] / block[:avg_size]) > ratio}
end

def get_paginator(blocks)  
  block = sort_by_count_numeric(blocks, 1)[0]
  (((block[:count_numeric] / block[:avg_size]) < 2.0) or (block[:avg_size] > 15.0)) ? nil : block[:doc]
end

def get_main_items(blocks)
  sort_by_score(reject_by_sim_ratio(blocks), 1)[0][:doc]
end

UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Safari/537.36"

DELTA = 0.3
AVG_SIZE = 90

read_from_url = -> (url) {
  open(url, "User-Agent" => UA).read.toutf8
}
read_from_file = -> (file) {
  File.open(file).read.toutf8
}

blocks = sim_blocks(get_doc(read_from_url.(ARGV[0])))

main_items = get_main_items(blocks)
paginator  = get_paginator(blocks)
ap main_items
ap paginator.to_html unless paginator.nil?
#ap sort_by_score(blocks, 10)
