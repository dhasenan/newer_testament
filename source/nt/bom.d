/** Processor for the Book of Mormon, Project Gutenberg edition */
module nt.bom;

import nt.books;

import std.conv;
import std.json;
import std.stdio;
import std.file;
import std.regex;
import std.typecons;
import std.algorithm.iteration : splitter;
import std.string;

Bible importBoM(string path)
{
    return toBookOfMormon(path.readText);
}

Bible toBookOfMormon(string text)
{
    auto cvr = regex("([0-9a-zA-Z ]*) ([0-9]+):([0-9]+)\n [0-9]+ ");
    auto bible = new Bible("Book of Mormon");
    foreach (part; text.splitter("\n\n"))
    {
        // It might be a verse header, a verse, a book preamble, a book name, or a chapter header.
        // There's a fair bit of redundancy, so we don't really need to worry about most.
        auto p = part.strip;
        if (p.length == 0) continue;
        auto m = matchFirst(p, cvr);
        if (m.empty) continue;
        auto book = m[1].strip;
        auto chapter = m[2].to!uint;
        auto verse = m[3].to!uint;
        auto t = m.post.strip;
        if (bible.books.length == 0 || bible.books[$-1].name != book)
        {
            bible.books ~= new Book(book);
        }
        if (bible.books[$-1].chapters.length == 0
                || bible.books[$-1].chapters[$-1].chapter != chapter)
        {
            bible.books[$-1].chapters ~= new Chapter(chapter);
        }
        bible.books[$-1].chapters[$-1].verses ~= new Verse(verse, t.replace("\n", " "));
    }
    return bible;
}
