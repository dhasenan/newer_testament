module nt.db;

import nt.books;
import nt.dictionary;

import d2sqlite3;
import jsonizer;

import std.algorithm;
import std.experimental.logger;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;

class DB
{
    this(string filename)
    {
        _db = Database(filename);
        _db.run(`PRAGMA foreign_keys = ON`);
        createTablesAndQueries;
    }

    void cleanup()
    {
        foreach (s; [_inserts, _gets, _updates, _removes])
        {
            foreach (k, ref v; s)
            {
                v.finalize;
                v = typeof(v).init;
            }
        }
        foreach (ref v; this.tupleof)
        {
            static if (is (typeof(v) == Statement))
            {
                v.finalize;
                v = typeof(v).init;
            }
        }

        import core.exception : AssertError, InvalidMemoryOperationError;
        try
        {
            _db.close;
        }
        // d2sqlite3 thinks we're in the GC right now in some cases.
        // We aren't.
        // Stop its silliness.
        catch (AssertError e) {}
        catch (InvalidMemoryOperationError e) {}
    }

    void beginTransaction()
    {
        if (_txDepth == 0)
            _db.run("BEGIN TRANSACTION");
        _txDepth++;
    }

    void commit()
    {
        if (_txDepth <= 0) return;
        _txDepth--;
        if (_txDepth == 0)
            _db.run("COMMIT TRANSACTION");
    }

    private template takeField(T, string name)
    {
        enum takeField = !is(typeof(() {
                // Not a static field
                auto tmp = __traits(getMember, T, name);
            }))
        && is(typeof(() {
                // Is a public field
                T tmp1 = void;
                auto tmp2 = __traits(getMember, tmp1, name);
           }))
        && !is(typeof(() {
                // Has no dbignore field
                // hasUDA only works on public fields
                static assert(hasUDA!(__traits(getMember, T, name), dbignore));
           }))
           ;
    }

    void save(T : DBObject)(T obj)
    {
        if (obj.id == 0)
        {
            auto op = _inserts[T.classinfo];
            op.reset;
            _getLastInsert.reset;
            bindFields(op, obj);
            op.execute;
            auto result = _getLastInsert.execute();
            obj.id = result.oneValue!ulong;
        }
        else
        {
            auto op = _updates[T.classinfo];
            op.reset;
            bindFields(op, obj);
            op.bind("@id", obj.id);
            op.execute();
        }
    }

    private void bindFields(T : DBObject)(ref Statement op, T obj)
    {
        enum fieldNames = FieldNameTuple!T;
        alias FieldTypes = Fields!T;
        static foreach (i, field; fieldNames)
        {
            static if (takeField!(T, field))
            {
                static if (is(FieldTypes[i] == Lex[]))
                {
                    op.bind("@" ~ field, toJSONString(__traits(getMember, obj, field)));
                }
                else
                {
                    op.bind("@" ~ field, __traits(getMember, obj, field));
                }
            }
        }
    }

    T get(T : DBObject)(ulong id)
    {
        auto query = _gets[T.classinfo];
        query.reset;
        query.bind("@id", id);
        return inflateSingle!T(query);
    }

    Word getWord(string w)
    {
        _fetcher.reset;
        _fetcher.bind(":word", w.toLower);
        return inflateSingle!Word(_fetcher);
    }

    auto allVerses(ulong bibleId)
    {
        _allVerses.reset;
        _allVerses.bind("@bibleId", bibleId);
        auto result = _allVerses.execute;
        return result.map!(x => inflate!Verse(x));
    }

    auto allSentences(ulong bibleId)
    {
        _allSentences.reset;
        _allSentences.bind("@bibleId", bibleId);
        auto result = _allSentences.execute;
        return result.map!(x => inflate!Sentence(x));
    }

    Bible bibleByName(string name)
    {
        _bibleByName.reset;
        _bibleByName.bind("@name", name);
        return inflateSingle!Bible(_bibleByName);
    }

    Book[] booksByBible(ulong bibleId)
    {
        _booksByBible.reset;
        _booksByBible.bind("@bibleId", bibleId);
        return inflateMany!Book(_booksByBible);
    }

    ThemedSentence[] sentencesByBook(ulong bookId, ulong modelId)
    {
        _sentencesByBook.reset;
        _sentencesByBook.bind("@bookId", bookId);
        _sentencesByBook.bind("@modelId", modelId);
        return inflateMany!ThemedSentence(_sentencesByBook);
    }

    Verse[] versesByBook(ulong bookId, ulong chapterNum)
    {
        _versesByBook.reset;
        _versesByBook.bind("@bookId", bookId);
        return inflateMany!Verse(_versesByBook);
    }

    Verse[] versesByChapter(ulong bookId, ulong chapterNum)
    {
        _versesByChapter.reset;
        _versesByChapter.bind("@bookId", bookId);
        _versesByChapter.bind("@chapterNum", chapterNum);
        return inflateMany!Verse(_versesByChapter);
    }

    void clearExistingAnalysis(ulong bibleId)
    {
        _clearExistingAnalysis.reset;
        _clearExistingAnalysis.bind("@bibleId", bibleId);
        _clearExistingAnalysis.execute;
    }

    void copyVersesByBook(ulong copyFromId, ulong copyToId)
    {
        _copyVersesByBook.reset;
        _copyVersesByBook.bind("@copyFromId", copyFromId);
        _copyVersesByBook.bind("@copyToId", copyToId);
        _copyVersesByBook.execute;
    }

    Sentence[] sentencesByTheme(ulong modelId, string theme)
    {
        _sentencesByTheme.reset;
        _sentencesByTheme.bind("@modelId", modelId);
        _sentencesByTheme.bind("@theme", theme);
        return inflateMany!Sentence(_sentencesByTheme);
    }

    ulong maxChapter(ulong bookId)
    {
        _maxChapter.reset;
        _maxChapter.bind("@bookId", bookId);
        return _maxChapter.execute.oneValue!ulong;
    }

private:
    Database _db;
    Statement _getLastInsert;
    Statement _fetcher;
    Statement _allSentences;
    Statement _allVerses;
    Statement _bibleByName;
    Statement _booksByBible;
    Statement _versesByChapter;
    Statement _versesByBook;
    Statement _sentencesByBook;
    Statement _clearExistingAnalysis;
    Statement _copyVersesByBook;
    Statement _sentencesByTheme;
    Statement _maxChapter;
    Statement[ClassInfo] _inserts, _updates, _gets, _removes;
    long _txDepth = 0;

    void createTablesAndQueries()
    {
        static foreach (m; __traits(allMembers, nt.books))
        {{
            mixin(`alias M = nt.books.`, m, `;`);
            static if (is (M == class) && !isAbstractClass!M && is (M : DBObject))
            {
                createTable!M;
            }
        }}

        createTable!Word;

        _getLastInsert = _db.prepare(`SELECT last_insert_rowid()`);
        _fetcher = _db.prepare(`SELECT * FROM words WHERE word = :word`);
        _allSentences = _db.prepare(`
                SELECT s.* FROM
                    books AS b
                    INNER JOIN sentences AS s ON s.bookId = b.id
                    WHERE b.bibleId = @bibleId
                    ORDER BY b.bookNumber ASC, s.chapterNum ASC, s.verse ASC`);
        _allVerses = _db.prepare(`
                SELECT v.* FROM
                    books AS b
                    INNER JOIN verses AS v ON v.bookId = b.id
                    WHERE b.bibleId = @bibleId
                    ORDER BY b.bookNumber ASC, v.chapterNum ASC, v.verse ASC`);
        _bibleByName = _db.prepare(`SELECT * FROM bibles WHERE name = @name`);
        _booksByBible = _db.prepare(`SELECT * FROM books WHERE bibleId = @bibleId
                    ORDER BY bookNumber ASC`);
        _versesByBook = _db.prepare(`SELECT * from verses
                WHERE verses.bookId = @bookId
                ORDER BY verses.chapterNum ASC, verses.verse ASC`);
        _sentencesByBook = _db.prepare(`SELECT ts.* from themedsentences AS ts
                INNER JOIN sentences s ON ts.sentenceId = s.id
                WHERE s.bookId = @bookId AND ts.themeModelId = @modelId
                ORDER BY s.chapterNum ASC, s.offset ASC`);
        _versesByChapter = _db.prepare(`SELECT * from verses
                WHERE verses.bookId = @bookId AND verses.chapterNum = @chapterNum
                ORDER BY verses.chapterNum ASC, verses.verse ASC`);
        _clearExistingAnalysis = _db.prepare(`DELETE FROM sentences
                WHERE bookId IN (SELECT id FROM books WHERE bibleId = @bibleId)`);
        // TODO make this auto-detect fields
        _copyVersesByBook = _db.prepare(`
                INSERT INTO verses (verse, text, analyzed, theme, chapterNum, bookId)
                SELECT verse, text, analyzed, theme, chapterNum, @copyToId
                FROM verses
                WHERE bookId = @copyFromId`);
        _sentencesByTheme = _db.prepare(`
                SELECT s.*
                FROM sentences AS s
                INNER JOIN themedsentences AS ts ON ts.sentenceId = s.id
                WHERE ts.theme = @theme AND ts.themeModelId = @modelId
                `);
        _maxChapter = _db.prepare(`SELECT MAX(chapterNum) FROM verses WHERE bookId = @bookId`);
    }

    // create a table, build default queries for it
    void createTable(T)()
    {
        assert(!(T.classinfo in _updates));
        assert(!(T.classinfo in _gets));
        assert(!(T.classinfo in _inserts));
        assert(!(T.classinfo in _removes));
        string table = T.classinfo.name[1 + T.classinfo.name.lastIndexOf(".") .. $] ~ "s";
        enum fieldNames = FieldNameTuple!T;
        alias FieldTypes = Fields!T;
        import std.array;

        string[] constraints;
        Appender!string mktable;
        mktable ~= `CREATE TABLE IF NOT EXISTS `;
        mktable ~= table;
        mktable ~= ` (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT`;
        Appender!string updsql, insql, argList;
        updsql ~= `UPDATE `
            ~ table
            ~ ` SET `;

        insql ~= `INSERT INTO `
            ~ table
            ~ `(id`;
        argList ~= "@id";
        auto first = true;
        static foreach (i, field; fieldNames)
        {
            static if (takeField!(T, field))
            {
                if (!first) updsql ~= ", ";
                first = false;

                mktable ~= ", ";
                mktable ~= field;
                static if (isIntegral!(FieldTypes[i]))
                {
                    mktable ~= " INTEGER";
                    if (field.endsWith("Id"))
                    {
                        constraints ~= `FOREIGN KEY (`
                            ~ field
                            ~ `) REFERENCES `
                            ~ field.replace("Id", "s")
                            ~ `(id)`;
                    }
                }
                else static if (isFloatingPoint!(FieldTypes[i]))
                {
                    mktable ~= " REAL";
                }
                else static if (is(FieldTypes[i] == ubyte[]))
                {
                    mktable ~= " BLOB";
                }
                else
                {
                    mktable ~= " TEXT";
                }

                insql ~= ", ";
                insql ~= field;

                argList ~= ", ";
                argList ~= "@";
                argList ~= field;

                updsql ~= field;
                updsql ~= " = @";
                updsql ~= field;
            }
        }
        insql ~= `) VALUES (`
            ~ argList.data
            ~ `)`;
        updsql ~= ` WHERE id = @id`;
        foreach (constraint; constraints)
        {
            mktable ~= `, `;
            mktable ~= constraint;
        }
        mktable ~= `)`;

        tracef("table creation: %s", mktable.data);
        _db.run(mktable.data);

        _updates[T.classinfo] = _db.prepare(updsql.data);
        _inserts[T.classinfo] = _db.prepare(insql.data);
        _removes[T.classinfo] = _db.prepare(`DELETE FROM ` ~ table ~ ` WHERE id = :id`);
        _gets[T.classinfo] = _db.prepare(`SELECT * FROM ` ~ table ~ ` WHERE id = :id`);
    }

    T inflate(T)(ref Row row)
    {
        enum fieldNames = FieldNameTuple!T;
        alias FieldTypes = Fields!T;
        auto obj = new T;
        // because FieldNameTuple only gets fields declared on this type
        obj.id = row["id"].as!ulong;
        static foreach (i, field; fieldNames)
        {
            static if (takeField!(T, field))
            {
                static if (isIntegral!(FieldTypes[i])
                        || isSomeString!(FieldTypes[i])
                        || isFloatingPoint!(FieldTypes[i]))
                {
                    __traits(getMember, obj, field) = row[field].as!(FieldTypes[i]);
                }
                else
                {
                    __traits(getMember, obj, field) =
                        fromJSONString!(FieldTypes[i])(row[field].as!string);
                }
            }
        }
        return obj;
    }

    T inflateSingle(T)(ref Statement stmt)
    {
        auto results = stmt.execute;
        if (results.empty) return null;
        auto row = results.front;
        return inflate!T(row);
    }

    T[] inflateMany(T)(ref Statement stmt)
    {
        import std.array : array;
        auto results = stmt.execute;
        if (results.empty) return null;
        return results.map!(x => this.inflate!T(x)).array;
    }
}

