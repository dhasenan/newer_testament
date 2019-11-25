module nt.sliceanddice;

import nt.db;
import nt.books;
import nt.util;

import jsonizer;

import core.stdc.stdlib : exit;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.experimental.logger;
import std.conv : to;

void slice(string[] args)
{
    string input, output;
    ulong id;
    string database;
    import std.getopt : config;
    argparse(args, "Split a Bible into canonical categories",
            config.required,
            "d|database", "database location", &database,
            config.required,
            "id", "id of the bible to split", &id);
    slice(database, id);
}

ulong[string] slice(string database, ulong id)
{
    ulong[string] ids;
    auto db = new DB(database);
    scope(exit) db.cleanup;
    auto bible = db.get!Bible(id);
    if (bible is null)
    {
        errorf("bible %s not found", id);
        exit(1);
    }
    auto books = db.booksByBible(id);
    foreach (cat, names; categories)
    {
        db.beginTransaction;
        auto slice = new Bible;
        slice.name = bible.name ~ " -- " ~ cat;
        foreach (book; books)
        {
            foreach (name; names)
            {
                // Lazily add the bible to the db in case we have empty segments
                if (slice.id == 0) db.save(slice);
                copyBook(db, book, slice.id);
            }
        }
        db.commit;
        writefln("%s: %s", slice.name, slice.id);
        ids[cat] = slice.id;
    }
    return ids;
}

private void copyBook(DB db, Book book, ulong newBibleId)
{
    auto bookCopy = new Book;
    bookCopy.name = book.name;
    bookCopy.id = 0;
    bookCopy.bookNumber = book.bookNumber;
    bookCopy.bibleId = newBibleId;
    db.save(bookCopy);
    db.copyVersesByBook(book.id, bookCopy.id);
}

void concat(string[] args)
{
    import std.getopt : config;
    ulong[] ids;
    string database;
    string name;
    argparse(args, "Combine several bibles into one",
            config.required, "d|database", "database file", &database,
            config.required, "n|name", "name of combined bible", &name);
    auto db = new DB(database);
    scope (exit) db.cleanup;

    auto bible = new Bible;
    bible.name = name;
    db.save(bible);

    db.beginTransaction;
    foreach (input; args)
    {
        auto b = db.booksByBible(input.to!ulong);
        foreach (book; b)
        {
            copyBook(db, book, bible.id);
        }
    }
    db.commit;
}

enum categories = [
    "pentateuch": ["genesis", "exodus", "leviticus", "numbers", "deuteronomy"],
    "ot-narrative": [
        "joshua", "judges", "ruth", "samuel", "kings", "chronicles", "ezra",
        "nehemiah", "esther", "tobit", "judith", "esdras"],
    "wisdom": [
        "job", "psalms", "proverbs", "ecclesiastes", "solomon", "canticles", "wisdom",
        "sirach",],
    "prophecy": [
        "isaiah", "jeremiah", "lamentations", "ezekiel", "daniel", "hosea", "joel",
        "amos", "obadiah", "jonah", "micah", "nahum", "habakkuk", "zephaniah",
        "haggai", "zechariah", "malachi", "revelation"
    ],
    "nt-narrative": ["matthew", "mark", "luke", "john", "acts", "maccabee", "baruch",],
    "epistle": [
		"romans", "corinthians", "corinthians", "galatians", "ephesians",
		"philippians", "colossians", "thessalonians", "timothy", "titus", "philemon",
		"hebrews", "james", "peter", "jude",
		// John is a case of name collision, so we call that out separately
        "1 john", "2 john", "3 john", "1st john", "2nd john", "3rd john", "of john",
    ]
];
