require 'nokogiri'
require "open-uri"
require 'kconv'
require 'pp'
require 'ap'

def remove_elem(doc)
  doc.xpath('//comment()').remove
  doc.xpath('//script').remove
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
    if doc.content.match /\A[-+]?[0-9]*\.?[0-9]+\Z/
      {type_numeric: 1}
    else
      nil
    end
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

DELTA = 0.15

def gamma_log(x)
  Math.log(gamma_basic(x, 10, 4.0)) * DELTA
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
    blocks << {
      path: doc.path,
      score: avg_sim + gamma_log(avg_size),
      avg_size: avg_size,
      avg_sim: avg_sim,
      count_numeric: calc_count_numeric(vecs),
      html: doc.to_html}
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

read_from_url = -> (url) {
  open(url).read.toutf8
}
read_from_file = -> (file) {
  File.open(file).read.toutf8
}
# ap sort_by_score(sim_blocks(get_doc(read_from_url.(ARGV[0]))), 20)
ap sort_by_count_numeric(sim_blocks(get_doc(read_from_url.(ARGV[0]))), 20)

