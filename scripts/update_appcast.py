"""Prepend a release to the Sparkle appcast. Args: appcast version build 'edSignature=.. length=..' url notes"""
import html, os, sys
from email.utils import formatdate

path, version, build, sig, url, notes = sys.argv[1:7]
item = f"""    <item>
      <title>Version {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>{html.escape(notes)}</p>]]></description>
      <enclosure url="{url}" {sig.strip()} type="application/octet-stream"/>
    </item>
"""
if os.path.exists(path):
    xml = open(path).read()
else:
    xml = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SayType</title>
    <link>https://frugoman.github.io/saytype-site/appcast.xml</link>
    <language>en</language>
<!--items-->
  </channel>
</rss>
"""
xml = xml.replace("<!--items-->\n", "<!--items-->\n" + item, 1)
open(path, "w").write(xml)
