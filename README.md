WikiText to Redmine+CKEditor Migration Tool
===================================================

This script parses **MediaWiki** XML exports, in WikiText markup, and pushes them into **Redmine** Wiki pages, in HTML5 format.

The basic logic for this is:

1.  Parse XML file using **Nokogiri**
2.  Tweak the MediaWiki markup (mainly search & replace)
3.  Convert MediaWiki markup to Textile using **Pandoc** binary (via **PandocRuby**)
4.  Tweak the Textile markup (mainly search & replace)
5.  Push all pages including their revisions *impersonating the original author* using **ActiveResource**

Used for migration from **MediaWiki** to **Redmine** wikis with CKEditor as the text formatting plugin.
Original Script: https://github.com/GSI/mrmt MediaWiki to Redmine Migration Tool (MRMT) (converts wikitext to textile)

Important Notes
---------------

-   The script assumes that all **revisions in the XML files are already in correct order**. Experience shows that this typically is the case when exporting from MediaWiki.
-   Due to restrictions in the Redmine API, this script adds the *original revision timestamp* **to the revision comment**. The revision itself will be associated with the current date (= date the migration is run).
-   MediaWiki contributor names will be converted to **lowercase Redmine user names**.
-   **Table of contents** (`{{>toc}}`) will be inserted at the top of every page.
-   If you want to import into different projects, **export one XML file per project** (see `--pagelist` option of MediaWiki's *dumpBackup.php*).
-   This script is known to work with XML exports from **MediaWiki version 1.18.1**.
-   The script will **delete existing** pages in the Redmine wiki, before it attempts each page load.
    -   To disable this behavior, edit push\_contents.rb, and set DELETE\_EXISTING\_PAGES = false

**Manual Deletion:
**\* The following **curl** command poses a **quick way to delete pages**: `curl -i -X DELETE --user "$ADMIN_API_KEY_HERE:$PASSWORD_IS_IRRELEVANT" https://example.plan.io/projects/$PROJECTNAME/wiki/$DESIRED_PAGENAME.xml`
**\* You may also use****curl**\* to get **more meaningful responses**. Example:
**\* `curl -i -H 'X-Redmine-Switch-User: importer' -X PUT -d content[text]="sometext" -d content[comments]="somecomment" --user "$ADMIN_API_KEY_HERE:$PASSWORD_IS_IRRELEVANT" https://example.plan.io/projects/$PROJECTNAME/wiki/$DESIRED_PAGENAME.xml`
** In case you want to **purge all \* existing wiki pages, use the following Ruby statement.
****\* `pages = WikiPage.get('index').collect { |p| p['title'] }; pages.each { |p| WikiPage.delete(p) }`


## Prerequisites
- Redmine version must be at least 2.2.0 in order to allow API access to wiki pages
- Pandoc 1.12.0.2 or newer (try your package management system, else http://johnmacfarlane.net/pandoc/installing.html)
- pandoc-ruby (https://github.com/alphabetum/pandoc-ruby).

Usage
-----

Follow these steps in the given order.

### In MediaWiki: Export XML file

1.  Deny all edits (see [MediaWiki: \$wgReadOnly(Disallow editing)](https://www.mediawiki.org/wiki/Manual:$wgReadOnly) and/or [MediaWiki: Preventing Access(Restrict editing by absolutely everyone)](https://www.mediawiki.org/wiki/Manual:Preventing_access#Restrict_editing_by_absolutely_everyone)).
2.  Export the wiki as XML (see [WikiMedia: Export(How to export)](https://meta.wikimedia.org/wiki/Help:Export#How_to_export)).
    - `su -m www -c "php ./maintenance/dumpBackup.php --full --pagelist=./pagelist --include-files > PATH_FOR/mediawiki-pages.xml"`

### In XML file: Clean up and remap users

1.  **Search and replace any contributor names** that you want to remap to certain other Redmine users.
    -   **VI-Example:** `:%s/<username>\cWikiSysop<\/username>/<username>admin<\/username>/`
    -   **Hint:** List all contributors of the XML file via `./list_contributors.rb PATH_TO/mediawiki-pages.xml` to verify only wanted contributors remain present.

2.  Optionally remove any unwanted contributions entirely.
3.  Redmine expects the default “Start Page” for the wiki to be named “Wiki”. This can be changed in project settings. a suggested value might be
     the project name, such as MYHPROJECT. If you choose to do this, then you might want to search and replace “Main\_Page” and “Main Page” to match your chosen name.
    Note that some auto-generated revisions in MediaWiki, like the “Main Page”, might be missing a contributor. The script is hard-coded to handle such cases by automatically assigning them to **“admin”**.

### In Redmine: Prepare wiki and users

1.  Set **upload size** higher than the size of the biggest file that you intend to upload.
    -   See option *Maximum attachment size* in in **Administration \> Settings** (e.g. https://example.plan.io/settings).

2.  **Rename any pages** that would clash with those to be imported.
3.  Ensure that all contributors of the MediaWiki instance **exist as users** in Redmine.
    -   See **Administration \> Users** (e.g. https://example.plan.io/users)

4.  Create a **role** with the *“Edit wiki pages”* and *“View wiki”* permissions.
    -   See **Administration \> Roles and permissions \> New role** (e.g. https://example.plan.io/roles/new)

5.  **Authorize the users** to edit the wiki of the project in question using the recently created role.
    -   See **Settings \> Members** within the project in question.
    -   **Hint:** List all contributors of the XML file via `./list_contributors.rb PATH_TO/mediawiki-pages.xml`.

### Script: push\_contents.rb

Use this script to push all MediaWiki revisions from the XML file to Redmine.

#### Syntax-Example

pre. SCRIPT\_NAME XML\_FILE REDMINE\_URL ADMIN\_API\_KEY
./push\_contents.rb ‘PATH\_TO/mediawiki.xml’ ‘https://example.plan.io/projects/\$PROJECTNAME/’ ‘ffff0000eeee1111dddd2222cccc3333bbbb4444’

***Important:** Ensure to provide the API key of an admin.*

### Script: upload\_files.rb

Use this script to upload all files to Redmine.

Note that the **directory name** of each image determines with which Redmine wiki page the uploaded file will be associated. Organize accordingly.

#### Example directory hierarchy

pre. images
├── one
│   ├── bar1.jpg \# will be associated with wiki page named “one”
│   ├── bar2.jpg \# will be associated with wiki page named “one”
│   └── bar3.jpg \# will be associated with wiki page named “one”
├── two
│   ├── bar1.jpg \# will be associated with wiki page named “two”
│   ├── bar2.jpg \# will be associated with wiki page named “two”
│   └── bar3.jpg \# will be associated with wiki page named “two”
└── foo
 ├── bar1.jpg \# will be associated with wiki page named “foo”
 ├── bar2.jpg \# will be associated with wiki page named “foo”
 └── bar3.jpg \# will be associated with wiki page named “foo”

#### Syntax-Example

pre. SCRIPT\_NAME IMAGE\_DIRECTORY REDMINE\_URL PROJECT\_NAME API\_KEY
./upload\_files.rb ‘\~/export\_to\_planio/images’ ‘https://example.plan.io’ ‘test’ ‘ffff0000eeee1111dddd2222cccc3333bbbb4444’

***Important:** Ensure to provide an API key with sufficient privileges.*

### In Redmine: Verify imported contents

At least the **current state of each wiki page** should be manually verified to be correct.

In addition, it’s advisable to check the number of history entries/revisions in **Redmine** against the one in **MediaWiki**.

Resources
---------

-   Redmine API documentation
    -   [Wiki pages](http://www.redmine.org/projects/redmine/wiki/Rest_WikiPages)
    -   [Using the REST API with Ruby](http://www.redmine.org/projects/redmine/wiki/Rest_api_with_ruby)
        -   Note that, as of 2013-09-25, the outlined example class declaration is incomplete.

-   http://apidock.com/rails/ActiveResource/Base
-   https://github.com/rails/activeresource\#active-resource-
-   https://github.com/edavis10/redmine/blob/master/config/routes.rb

License
-------

The **MediaWiki to Redmine Migration Tool** is released under the [MIT License](http://www.opensource.org/licenses/MIT).
