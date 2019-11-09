/** World English Bible input. The World English Bible text is public domain, but the term "World
 * English Bible" is trademarked by eBible.org.
 *
 * The World English Bible is readily available in USFM format, a markup standard for scripture
 * vaguely reminiscent of LaTeX.
 */
module nt.input.web;

import nt.books;
import nt.input.usfm;

import std.algorithm;
import std.net.curl;
import std.range;
import std.string;
import std.stdio;
import std.file;
import std.zip;

// This Bible is a zip file containing USFM text.
// Each book is a separate file within the archive.
// There are two USFM files that aren't Bible books: the frontmatter and the glossary.
Bible importWEB(string filename)
{
    if (!exists(filename))
    {
        downloadWEB(filename);
    }
    auto z = new ZipArchive(read(filename));
    auto bible = new Bible();
    bible.name = "World English Bible";
    auto books = z.directory
        .keys
        .filter!(x => x.endsWith(".usfm"))
        .filter!(x => !x.contains("00-FRTeng-web.usfm"))
        .filter!(x => !x.contains("106-GLOeng-web.usfm"))
        .array
        .sort
        .array;
    foreach (i, bookName; books)
    {
        auto member = z.directory[bookName];
        z.expand(member);
        auto book = usfmToBook(cast(string)member.expandedData);
        bible.books ~= book;
    }
    foreach (verse; bible.allVerses)
    {
        verse.text = verse.text
            .replace("—", " — ")
            .replace("eThen", "Then")
            .replace("ofAdin", "of Adin")
            ;
    }
    return bible;
}

void downloadWEB(string target)
{
    std.net.curl.download("https://ebible.org/Scriptures/eng-web_usfm.zip", target);
}
