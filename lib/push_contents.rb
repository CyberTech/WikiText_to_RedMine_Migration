#!/usr/bin/env ruby

# Avoid issue with 1.9 where string.gsub will complain of illegal char in ASCII string.
if RUBY_VERSION =~ /1.9/
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
end


# explicitly require older 'builder' gem in order to avoid conflicts
gem 'builder', '~> 3.0.4'
# TODO remove
# gem 'nokogiri', '~> 1.6.0'
gem 'pandoc-ruby', '~> 0.7.5'

# TODO remove
#require 'nokogiri' # for parsing the MediaWiki XML export file
require 'pandoc-ruby' # for converting MediaWiki to various output markups
require 'active_resource' # for talking to Redmine
require_relative 'common/xml_handler.rb'

# Edit the following settings as required.

DELETE_EXISTING_PAGES = true

# The prefix defined in this constant will be removed from MediaWiki page titles.
REMOVE_PAGE_TITLE_PREFIX = ''

# Comments will be prefixed with the date of the original MediaWiki revision.
# An example using the default setting would be [2013-02-01 01:20:33]
COMMENT_DATE_FORMAT = '[%Y-%m-%d %H:%M:%S]'

# Certain MediaWiki pages may contain revisions without a contributor.
# The most common example is the first revision of the main page.
# This constant defines the fallback user name in such cases.
DEFAULT_CONTRIBUTOR = 'admin'


SOURCE_XML = ARGV[0]  # eg 'PATH_TO/mediawiki.xml'
PROJECT_URL = ARGV[1] # eg 'https://example.plan.io/projects/$PROJECT_NAME/'
API_KEY = ARGV[2]     # eg 'ffff0000eeee1111dddd2222cccc3333bbbb4444'


class WikiPage < ActiveResource::Base
  class << self
    attr_writer :connection
  end

  self.site = PROJECT_URL
  self.collection_name = 'wiki'
  self.format = :xml

  # Passing the API key as username is sufficient for authentication.
  # This script is intended to use Redmines' User Impersonation feature.
  # Thus an admin (!) API key is required here.
  self.user = API_KEY
  # self.user = 'admin'
  # self.password = 'password'

  def self.impersonate_user(username)
    self.headers['X-Redmine-Switch-User'] = username
  end
end

def optimize_mediawiki_markup(markup)
	# convert to newer list syntax
	markup.gsub!(/^ \- /, '** ')

	# :* is either not legal wikitext, or Pandoc wikitext reader doesn't support it. Either way, convert it to the most likely (least damaging) alternative
	markup.gsub!(/^:\*/) { '**'}

	# As the utilized Pandoc version fails to interpret foreign tags like '[[Datei:...]]', rename them to English variant.
	# NOTE you may need to add your own customizations here
	markup.gsub!(/\[\[Datei:/,'[[File:')
	markup.gsub!(/\[\[Bild:/,'[[File:')

	# Now, a common mediawiki format is
	#	* Foo
	#	: Indented description of foo
	markup.gsub!(/^([*]+)(.*)(?<!\n)\n(:+)/) { $1 + $2 + "\n" + '*' * ($1.length.to_i+1) }

	# Protect these from conversion, as redmine wants it to be in mediawiki-style format, for the wiki pages
	#markup.gsub!(/\[\[((?!HTTP:).+)\]\]/im,'<MW_DOUBLEBRACKET>\\1</MW_DOUBLEBRACKET>')
	#markup.gsub!(/\[((?!HTTP:).+)\]/im,'<MW_SINGLEBRACKET>\\1</MW_SINGLEBRACKET>')

	# Fix improper syntax with missing space following markup
	markup.gsub!(/^([#:*]+)([^ ])/) { $1 + " "  + $2}

	markup
end

def optimize_markup(markup)

	markup
end

# Accepts MediaWiki-formated input and returns HTML5 markup with RedMine Wiki exceptions
def convert_wikitext(markup)
#p "Original: " + markup[markup.index("Foo")-50,100] if markup.index("Foo")

  markup = optimize_mediawiki_markup(markup)

  markup = PandocRuby.convert(markup, { :from => :mediawiki, :to => :'html5' }, 'normalize', 'preserve-tabs', 'section-divs', )

  markup = optimize_markup(markup)

  markup
end

def rename_page_title(title)
  title.gsub!(/\A#{REMOVE_PAGE_TITLE_PREFIX}/, '')
  title.gsub!('.','')

  title
end

def delete_wiki_page(title)
  p "Deleting #{title} ..."
  WikiPage.delete(title)
end

def handle_forbidden_view_access(fa, delete_page = false)
  p "The following exception typically means that the impersonated user ('#{WikiPage.headers['X-Redmine-Switch-User']}') is missing privileges to read the wiki in question. Verify that the user has the 'View wiki' permission set."
  delete_wiki_page(page_title) if delete_page
  raise fa
end

def handle_forbidden_write_access(fa)
  p "The following exception typically means that the impersonated user ('#{WikiPage.headers['X-Redmine-Switch-User']}') is missing privileges to write to the wiki in question. Verify that the user has the 'Edit wiki pages' permission set."
  delete_wiki_page(page_title)
  raise fa
end

def push_all_revisions_to_redmine
  doc = get_xml_file_handle(SOURCE_XML)

  doc.xpath('//xmlns:page').each do |p|
    revision_count = p.css('revision').count
    page_title = rename_page_title(p.css('title').text)

	# Uncomment for testing imports; set PAGETITLE to the page you want it to test importing
	#next if page_title.index("PAGETITLE").nil?

    p "Pushing #{revision_count} revisions to #{page_title} (renamed from #{p.css('title').text}) ..."

    begin
		if (WikiPage.find(page_title) && DELETE_EXISTING_PAGES)
			p "WARNING: A page titled '#{page_title}' already exists. Deleting."
			delete_wiki_page(page_title)
		end
		p "WARNING: A page titled '#{page_title}' still exists. Skipping." if WikiPage.find(page_title)

	# WikiPage.find access denied (likely no wiki access)
    rescue ActiveResource::ForbiddenAccess => fa
			handle_forbidden_view_access(fa)

	# WikiPage.find failed to find the page, so we're clear to make it
    rescue ActiveResource::ResourceNotFound
      previous_version = 0

      p.css('revision').each_with_index do |r, i|
        # TODO refactor into a class
        timestamp = DateTime.strptime(r.css('timestamp').text, '%Y-%m-%dT%H:%M:%S%Z') # e.g. 2011-08-10T10:35:31Z
        date_time = timestamp.strftime(COMMENT_DATE_FORMAT)
        username = (r.css('contributor username').text).downcase || DEFAULT_CONTRIBUTOR
        text_as_mediawiki = r.css('text').text
		text_as_output= '<h2><span style="color:#800000;">' + page_title + "</span></h2>\n\n<p>{{&gt;toc}}</p>\n\n" + convert_wikitext(text_as_mediawiki)

        comment = r.css('comment').text
        comment_for_redmine = "#{date_time} #{comment}"

        p "Importing revision #{i+1}/#{revision_count} of '#{page_title}' from #{timestamp}, impersonating #{username}"
        WikiPage.impersonate_user(username)

        page = WikiPage.new( { id: page_title,
                               text: text_as_output, comments: comment_for_redmine,
                               version: previous_version }, true )

        begin
          page.save

        rescue ActiveResource::ResourceConflict => rc
          # NOTE if a new revision leaves all the text untouched, page.save will return true without updating
          # the wiki. This implies that 'version' in the wiki will stay untouched and thus behind, causing this
          # ResourceConflict exception on the _next_ update that actually _does_ update the text.
          # TODO file bug report
          # As a workaround, the last version is fetched in such cases.
          p "Handling #{rc.class} ..."

					begin
            page.version = previous_version = (WikiPage.find(page_title)).version.to_i
					rescue ActiveResource::ForbiddenAccess => fa
            handle_forbidden_view_access(fa, true)
					end

          p "Reset version number to #{page.version}. Retrying ..."
          page.save

        rescue ActiveResource::ForbiddenAccess => fa
					handle_forbidden_write_access(fa)

        rescue ActiveResource::ClientError => ce
          p "The following exception typically means that the impersonated user ('#{username}') is missing in Redmine or that the desired page title contains unsupported symbols."
          delete_wiki_page(page_title)
          raise ce

        end

        previous_version += 1
      end
    end

  end
end

push_all_revisions_to_redmine
