#!/usr/bin/env ruby
require 'erb'

module TAO; end unless defined? TAO

class TAO::RDFizer
	# if mode == :spans then produces span descriptions
	# if mode == :annotations then produces annotation descriptions
	# if mode == nil then produces both
	def initialize(mode = nil)
		@mode = mode
		template = if !mode.nil? && mode == :spans
			ERB_SPANS_TTL
		else
			ERB_ANNOTATIONS_TTL
		end

		@tao_ttl_erb = ERB.new(template, nil, '-')
		@prefix_ttl_erb = ERB.new(ERB_PREFIXES_TTL, nil, '-')
	end

	def rdfize(annotations_col)
		# namespaces
		namespaces = {}

		anns = annotations_col.first
		anns[:namespaces].each {|n| namespaces[n[:prefix]] = n[:uri]} unless anns[:namespaces].nil?

		unless @mode ==:spans
			prefix_for_this = anns[:project].downcase.gsub(/ /, '_')
			raise ArgumentError, "'#{prefix_for_this}' is a reserved prefix for this project." if namespaces.has_key?(prefix_for_this)
			project_uri = 'http://pubannotation.org/projects/' + anns[:project]
			namespaces[prefix_for_this] = project_uri + '/'
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

			begin
				# denotations preprocessing
				_denotations.each do |d|
					span_uri = "<#{text_uri}/spans/#{d[:span][:begin]}-#{d[:span][:end]}>"
					d[:span_uri] = span_uri
					d[:obj_uri] = "#{prefix_for_this}:#{text_id}-#{d[:id]}"
					d[:cls_uri] = find_uri(d[:obj], namespaces, prefix_for_this)
				end

				# relations preprocessing
				_relations.each do |r|
					r[:subj_uri] = "#{prefix_for_this}:#{text_id}-#{r[:subj]}"
					r[:obj_uri] = "#{prefix_for_this}:#{text_id}-#{r[:obj]}"
					r[:pred_uri] = find_uri(r[:pred], namespaces, prefix_for_this)
				end
			rescue ArgumentError => e
				raise ArgumentError, "[#{sourcedb}-#{sourceid}] " + e
			end

			unless @mode == :annotations
				# collect spans
				_spans = _denotations.map{|d| d[:span]}
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
					_spans[i][:children] = []
				end

				(0 ... num).each do |i|
					# find the first following span
					j = i + 1

					while j < num && _spans[j][:begin] < _spans[i][:end]
						unless include_parent?(_spans[i][:children], _spans[j])
							_spans[i][:children] << _spans[j]
						end
						j += 1
					end

					# find adjacent positions
					fp = _spans[i][:end]
					fp += 1 while fp < len && text[fp].match(/\s/)
					next if fp == len

					# index adjacent spans
					while j < num && _spans[j][:begin] == fp
						_spans[i][:followings] << _spans[j]
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

	private

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

	def find_uri (label, namespaces, prefix_for_this)
		raise ArgumentError, "A label including a whitespace character found: #{label}." if label.match(/\s/)
		delimiter_position = label.index(':')
		if !delimiter_position.nil? && namespaces.keys.include?(label[0...delimiter_position])
			label
		elsif label =~ %r[^https?://]
			"<#{label}>"
		else
			clabel = if label.match(/^\W+$/)
				'SYM'
			else
				label.sub(/^\W+/, '').sub(/\W+$/, '').gsub(/ +/, '_')
			end
			namespaces.has_key?('_base') ? "<#{clabel}>" : "#{prefix_for_this}:#{clabel}"
		end
	end

	ERB_ANNOTATIONS_TTL = <<~HEREDOC
		<% denotations.each do |d| -%>
		<%= d[:obj_uri] %> tao:denoted_by <%= d[:span_uri] %> ;
			rdf:type <%= d[:cls_uri] %> .
		<% end -%>
		<%# relations -%>
		<% relations.each do |r| -%>
		<%= r[:subj_uri] %> <%= r[:pred_uri] %> <%= r[:obj_uri] %> .
		<% end -%>
	HEREDOC

	ERB_SPANS_TTL = <<~HEREDOC
		<% spans.each do |s| -%>
		<%= s[:span_uri] %> rdf:type tao:Text_span ;
		<% s[:followings].each do |s| -%>
			tao:followed_by <%= s[:span_uri] %> ;
		<% end -%>
		<% s[:children].each do |s| -%>
			tao:contains <%= s[:span_uri] %> ;
		<% end -%>
			tao:has_text <%= s[:text].inspect %> ;
			tao:belongs_to <<%= s[:source_uri] %>> ;
			tao:begins_at <%= s[:begin] %> ;
			tao:ends_at <%= s[:end] %> .
		<% end -%>
	HEREDOC

	ERB_PREFIXES_TTL = <<~HEREDOC
		@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
		@prefix tao: <http://pubannotation.org/ontology/tao.owl#> .
		<%# namespaces -%>
		<% namespaces.each_key do |p| -%>
		<% if p == '_base' -%>
		@base <<%= namespaces[p] %>> .
		<% else -%>
		@prefix <%= p %>: <<%= namespaces[p] %>> .
		<% end -%>
		<% end -%>
	HEREDOC

end
