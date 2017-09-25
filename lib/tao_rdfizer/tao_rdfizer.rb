#!/usr/bin/env ruby
require 'erb'

module TAO; end unless defined? TAO

class TAO::RDFizer
  # if mode == :spans then produces span descriptions
  # if mode == :annotations then produces annotation descriptions
  # if mode == nil then produces both
  def initialize(mode = nil)
  	@mode = mode
		template_filename = unless mode.nil?
			if mode == :annotations
				'view/tao_annotations_ttl.erb'
			elsif mode == :spans
				'view/tao_spans_ttl.erb'
			else
				'view/tao_ttl.erb'
			end
		else
			'view/tao_ttl.erb'
		end
		@tao_ttl_erb = ERB.new(File.read(template_filename), nil, '-')
		@prefix_ttl_erb = ERB.new(File.read("view/prefixes_ttl.erb"), nil, '-')
  end

	def rdfize(annotations_col)
		# namespaces
		namespaces = {}
		anns = annotations_col.first
		anns[:namespaces].each {|n| namespaces[n[:prefix]] = n[:uri]} unless anns[:namespaces].nil?
		raise ArgumentError, "'prj' is a reserved prefix." if namespaces.has_key?('prj')

		unless @mode ==:spans
			project_uri = 'http://pubannotation.org/projects/' + anns[:project] unless @mode ==:spans
			namespaces['prj'] = project_uri + '/' 
		end

		denotations = []
		relations = []
		spans = []

		annotations_col.each do |annotations|
			text = annotations[:text]
			text_uri = annotations[:target]
			text_id = begin
				sourcedb, sourceid, divid = get_target_info(text_uri)
				divid.nil? ? "#{sourcedb}-#{sourceid}" : "#{sourcedb}-#{sourceid}-#{divid}"
			end

			# denotations and relations
			_denotations = annotations[:denotations]
			_relations = annotations[:relations]
			_denotations = [] if _denotations.nil?
			_relations = [] if _relations.nil?
			if @mode == :spans && annotations.has_key?(:tracks)
				annotations[:tracks].each do |track|
					_denotations += track[:denotations]
					_relations += track[:relations]
				end
			end

			# denotations preprocessing
			_denotations.each do |d|
				span_uri = "<#{text_uri}/spans/#{d[:span][:begin]}-#{d[:span][:end]}>"
				d[:span_uri] = span_uri
				d[:obj_uri] = "prj:#{text_id}-#{d[:id]}"
				d[:cls_uri] = find_uri(d[:obj], namespaces)
			end

			# relations preprocessing
			_relations.each do |r|
				r[:subj_uri] = "prj:#{text_id}-#{r[:subj]}"
				r[:obj_uri] = "prj:#{text_id}-#{r[:obj]}"
				r[:pred_uri] = find_uri(r[:pred], namespaces)
			end

			unless @mode == :annotations
				# collect spans
				_spans = _denotations.map{|d| d[:span]}
				position = 0
				annotations[:text].scan(/[^\W]*\W/).each do |tok|
					_spans << {:begin => position, :end => position + tok.index(/\W/)}
					position += tok.length
				end
				_spans.uniq!

				# add_infomation
				_spans.each do |s|
					s[:span_uri] = "<#{text_uri}/spans/#{s[:begin]}-#{s[:end]}>"
					s[:source_uri] = text_uri
					s[:text] = text[s[:begin] ... s[:end]]
				end

				# index
				spanh = _spans.inject({}){|r, s| r[s[:span_uri]] = s; r}

				# add denotation information
				_denotations.each do |d|
					span_uri = d[:span_uri]
					if spanh[span_uri][:denotations].nil?
						spanh[span_uri][:denotations] = [d]
					else
						spanh[span_uri][:denotations] << d
					end
				end

				_spans.sort!{|a, b| (a[:begin] <=> b[:begin]).nonzero? || b[:end] <=> a[:end]}

				## begin indexing
				len = text.length
				num = _spans.length

				# initilaize the index
				(0 ... num).each do |i|
					_spans[i][:followings] = []
					_spans[i][:precedings] = []
					_spans[i][:children] = []
				end

				(0 ... num).each do |i|
					# index the embedded spans
					j = i + 1
					while j < num && _spans[j][:begin] < _spans[i][:end]
						unless include_parent?(_spans[i][:children], _spans[j])
							_spans[i][:children] << _spans[j]
							_spans[j][:parent] = _spans[i]
						end
						j += 1
					end

					# find the following position
					fp = _spans[i][:end]
					fp += 1 while fp < len && text[fp].match(/\s/)
					next if fp == len

					# index the following spans
					while j < num && _spans[j][:begin] == fp
						_spans[i][:followings] << _spans[j]
						_spans[j][:precedings] << _spans[i]
						j += 1
					end 
				end
			end

			denotations += _denotations
			relations += _relations
			spans += _spans unless @mode == :annotations
		end

		ttl = @prefix_ttl_erb.result(binding) + @tao_ttl_erb.result(binding)
	end

	def include_parent?(spans, span)
		# spans.each{|s| return true if (s[:begin] <= span[:begin] && s[:end] > span[:end]) || (s[:begin] < span[:begin] && s[:end] >= span[:end])}
		spans.each{|s| return true if s[:begin] <= span[:begin] && s[:end] >= span[:end]}
		return false
	end

	def get_target_info (text_uri)
		sourcedb = (text_uri =~ %r|/sourcedb/([^/]+)|)? $1 : nil
		sourceid = (text_uri =~ %r|/sourceid/([^/]+)|)? $1 : nil
		divid    = (text_uri =~ %r|/divs/([^/]+)|)? $1 : nil

		return sourcedb, sourceid, divid
	end

	def find_uri (label, namespaces)
		delimiter_position = label.index(':')
		if !delimiter_position.nil? && namespaces.keys.include?(label[0...delimiter_position])
			label
		elsif label =~ %r[^https?://]
			"<#{label}>"
		else
			clabel = if label.match(/^\W+$/)
				'SYM'
			else
				label.sub(/^\W+/, '').sub(/\W+$/, '')
			end
			namespaces.has_key?('_base') ? "<#{clabel}>" : "prj:#{clabel}"
		end
	end
end
