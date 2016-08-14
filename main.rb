require 'nokogiri'
require "open-uri"
require 'kconv'

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
    [vec.values, vec.values].map {|val| val.reduce(&:*)}.reduce(&:+))
  vec.map do |k, v|
    [k, v.to_f / sum.to_f]
  end.to_h
end

def calc(vecs)
  return 0.0 if vecs.size <= 1
  vecs_norm = vecs.map {|vec| normalize(vec)}
  val = vecs_norm.map.with_index { |x, i|
    vecs_norm.map.with_index {|y, j|
      i != j ? inner_product(x, y) : 0}.reduce(&:+) }.reduce(&:+)
  val.to_f / vecs_norm.size
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
    nil # skip
  when Nokogiri::XML::NodeSet
    nil # skip
  when Nokogiri::XML::Element
    return nil if doc.name == "br"
    val_elem(doc)
  else
    raise "unknown attributes: #{doc.class}"
  end
end

def merge!(arr, x)
  x.each do |k, v|
    if arr.key? k
      arr[k] += v
    else
      arr[k] = v
    end
  end
  arr
end

def merge_hash(arr)
  arr.reduce {|accum, x| merge!(accum, x) unless x.nil?}
end

def dfs(doc)
  children = doc&.children
  return val(doc) if children.empty?
  arr = children.map do |elem|
    dfs(elem)
  end + [val(doc)]
  arr = arr.reject(&:nil?)
  if calc(arr) > 5.0
    puts doc.to_html
    puts calc(arr)
    p arr
    puts "=========="
  end
  hash = merge_hash(arr)
  return hash
end

read_from_url = -> (url) {
  open(url).read.toutf8
}
read_from_file = -> (file) {
  File.open(file).read  
}

html = read_from_url.(ARGV[0])

doc = Nokogiri::HTML html
remove_elem(doc)
$res = []
dfs(doc.xpath('//body'))

