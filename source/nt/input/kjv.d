/** Input processor for KJV, Project Gutenberg edition */
module nt.input.kjv;

import nt.books;
import nt.db;
import nt.names;
import nt.nlp;
import nt.util;

import std.conv;
import std.json;
import std.stdio;
import std.string;
import std.algorithm;
import std.file;
import std.regex;
import sai = std.algorithm.iteration;
import std.typecons;

Bible importKJV(string path, DB db)
{
    auto text = path.readText;

    auto cvr = regex("([0-9]+):([0-9]+)");

    auto bible = new Bible("King James Bible");
    db.save(bible);
    Book book;
    foreach (part; sai.splitter(text, "\n\n\n"))
    {
        auto p = part.strip;
        auto m = matchFirst(p, cvr);
        if (m.empty)
        {
            if (book) bible.books ~= book;
            book = new Book;
            book.bookNumber = bible.books.length + 1;
            book.bibleId = bible.id;
            book.name = p.strip;
            db.save(book);
            continue;
        }
        auto splat = std.regex.splitter!(Yes.keepSeparators)(p, cvr);
        while (!splat.empty)
        {
            m = matchFirst(splat.front, cvr);
            if (m.empty)
            {
                splat.popFront;
                m = matchFirst(splat.front, cvr);
            }
            auto ch = m[1].to!uint;
            auto v = m[2].to!uint;
            foreach (i; book.chapters.length .. ch)
            {
                auto chapter = new Chapter(cast(uint)i + 1);
                chapter.bookId = book.id;
                db.save(chapter);
                book.chapters ~= chapter;
            }

            splat.popFront;
            auto cleaned = splat.front
                // Paragraph separator isn't whitespace and won't get stripped
                .replace("\n\n", newParagraphMark)
                .strip
                .replace("\n", " ");
            auto verse = new Verse(v, cleaned);
            verse.chapterId = book.chapters[$-1].id;
            book.chapters[ch - 1].verses ~= verse;
            db.save(verse);
            splat.popFront;
        }
    }
    bible.books ~= book;
    return bible;
}

