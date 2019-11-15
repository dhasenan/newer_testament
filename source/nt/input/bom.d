/** Processor for the Book of Mormon, Project Gutenberg edition */
module nt.input.bom;

import nt.books;
import nt.db;

import std.conv;
import std.json;
import std.stdio;
import std.file;
import std.regex;
import std.typecons;
import std.algorithm.iteration : splitter;
import std.string;

Bible importBoM(string path, DB db)
{
    auto text = path.readText;

    auto cvr = regex("([0-9a-zA-Z ]*) ([0-9]+):([0-9]+)\n [0-9]+ ");
    auto bible = new Bible("Book of Mormon");
    db.save(bible);
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
            auto bk = new Book(book);
            bk.bookNumber = bible.books.length + 1;
            bk.bibleId = bible.id;
            bible.books ~= bk;
            db.save(bk);
        }
        if (bible.books[$-1].chapters.length == 0
                || bible.books[$-1].chapters[$-1].chapter != chapter)
        {
            auto ch = new Chapter(chapter);
            auto bk = bible.books[$-1];
            ch.bookId = bk.id;
            db.save(ch);
            bk.chapters ~= ch;
        }
        auto v = new Verse(verse, t.replace("\n", " "));
        auto ch = bible.books[$-1].chapters[$-1];
        v.chapterId = ch.id;
        db.save(v);
        ch.verses ~= v;
    }
    return bible;
}
