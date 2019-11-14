module nt.db;

import d2sqlite3;
import jsonizer;
import nt.books;
import nt.dictionary;
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
        createTablesForBookDbObjects;
    }

    void cleanup()
    {
        _fetcher.finalize;
        foreach (s; [_inserts, _gets, _updates, _removes])
        {
            foreach (k, v; s)
            {
                v.finalize;
            }
        }
        _db.close;
    }

    void beginTransaction()
    {
        _db.run("BEGIN TRANSACTION");
    }

    void commit()
    {
        _db.run("COMMIT TRANSACTION");
    }

    void importBible(Bible bible)
    {
        save(bible);
        foreach (book; bible.books)
        {
            book.bibleId = bible.id;
            save(book);
            foreach (chapter; book.chapters)
            {
                chapter.bookId = book.id;
                save(chapter);
                foreach (verse; chapter.verses)
                {
                    verse.chapterId = chapter.id;
                    save(verse);
                }
            }
        }
    }

    private template takeField(T, string name)
    {
        enum takeField = !is(typeof(() {
                    auto tmp = __traits(getMember, T, name);
                    }))
            && !hasUDA!(__traits(getMember, T, name), dbignore);
    }

    void save(T : DBObject)(T obj)
    {
        enum fieldNames = FieldNameTuple!T;
        alias FieldTypes = Fields!T;

        Statement op = _updates[T.classinfo];
        if (obj.id == uuidZero)
        {
            obj.id = randomUUID;
            op = _inserts[T.classinfo];
        }
        op.reset;
        static foreach (i, field; fieldNames)
        {
            static if (takeField!(T, field))
            {
                static if (is(FieldTypes[i] == Lex[]))
                {
                    op.bind(field, toJSONString(__traits(getMember, obj, field)));
                }
                else static if (is(FieldTypes[i] == UUID))
                {
                    op.bind(field, __traits(getMember, obj, field).toString);
                }
                else
                {
                    op.bind(field, __traits(getMember, obj, field));
                }
            }
        }
        op.execute();
    }

    T get(T : DBObject)(UUID id)
    {
        auto query = _gets[T.classinfo];
        query.reset;
        query.bind("id", id.toString);
        auto results = query.execute;
        if (results.empty) return null;
        auto row = results.front;
        return inflate!T(row);
    }

    Word getWord(string w)
    {
        _fetcher.reset;
        _fetcher.bind(":word", w.toLower);
        auto results = _fetcher.execute;
        if (results.empty) return null;
        auto row = results.front;
        return inflate!Word(row);
    }

    private:
    Database _db;
    Statement _updater, _fetcher, _inserter;
    Statement[ClassInfo] _inserts, _updates, _gets, _removes;

    void createTablesForBookDbObjects()
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

        _db.run(`PRAGMA foreign_keys = ON`);

        // Constraints; we don't intuit them currently
        _db.run(`ALTER TABLE words ADD CONSTRAINT uniq_words_word UNIQUE words(word)`);
        _db.run(`ALTER TABLE books ADD CONSTRAINT fk_books_bibles
                FOREIGN KEY (bibleId) REFERENCES bibles(id)`);
        _db.run(`ALTER TABLE chapters ADD CONSTRAINT fk_chapters_books
                FOREIGN KEY (bookId) REFERENCES books(id)`);
        _db.run(`ALTER TABLE verses ADD CONSTRAINT verses_chapters
                FOREIGN KEY (chapterId) REFERENCES chapter(id)`);

        _fetcher = _db.prepare(`SELECT * FROM words WHERE word = :word`);
    }

    // create a table, build default queries for it
    void createTable(T)()
    {
        string table = T.classinfo.name[1 + T.classinfo.name.lastIndexOf(".") .. $] ~ "s";
        enum fieldNames = FieldNameTuple!T;
        alias FieldTypes = Fields!T;
        import std.array;

        Appender!string mktable;
        mktable ~= `CREATE TABLE IF NOT EXISTS `;
        mktable ~= table;
        mktable ~= ` (id TEXT NOT NULL PRIMARY KEY`;
        Appender!string updsql, insql, argList;
        updsql ~= `UPDATE `
            ~ table
            ~ `SET `;

        insql ~= `INSERT INTO `
            ~ table
            ~ `(`;
        auto first = true;
        static foreach (i, field; fieldNames)
        {
            static if (takeField!(T, field))
            {
                if (!first)
                {
                    insql ~= ", ";
                    argList ~= ", ";
                    updsql ~= ", ";
                }

                mktable ~= ", ";
                mktable ~= field;
                static if (isIntegral!(FieldTypes[i]))
                {
                    mktable ~= " INTEGER";
                }
                else static if (isFloatingPoint!(FieldTypes[i]))
                {
                    mktable ~= " REAL";
                }
                else
                {
                    mktable ~= " TEXT";
                }

                insql ~= field;

                argList ~= ":";
                argList ~= field;

                updsql ~= field;
                updsql ~= " = :";
                updsql ~= field;

                first = false;
            }
        }
        insql ~= `) VALUES (`
            ~ argList.data
            ~ `)`;
        updsql ~= ` WHERE id = :id`;

        tracef("%s create table sql: %s", mktable.data);
        tracef("%s insert sql: %s", insql.data);
        tracef("%s update sql: %s", insql.data);

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
        obj.id = UUID(row["id"].as!string);
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
                else static if (is(FieldTypes[i] : UUID))
                {
                    __traits(getMember, obj, field) = UUID(row[field].as!string);
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
}

