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
        _db.run(`PRAGMA foreign_keys = ON`);
        createTablesForBookDbObjects;
    }

    void cleanup()
    {
        _fetcher.finalize;
        foreach (s; [_inserts, _gets, _updates, _removes])
        {
            foreach (k, ref v; s)
            {
                v.finalize;
                v = typeof(v).init;
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
        op.bind("@id", obj.id.toString);
        static foreach (i, field; fieldNames)
        {
            static if (takeField!(T, field))
            {
                static if (is(FieldTypes[i] == Lex[]))
                {
                    op.bind("@" ~ field, toJSONString(__traits(getMember, obj, field)));
                }
                else static if (is(FieldTypes[i] == UUID))
                {
                    op.bind("@" ~ field, __traits(getMember, obj, field).toString);
                }
                else
                {
                    op.bind("@" ~ field, __traits(getMember, obj, field));
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
        return inflateSingle(query);
    }

    Word getWord(string w)
    {
        _fetcher.reset;
        _fetcher.bind(":word", w.toLower);
        return inflateSingle!Word(_fetcher);
    }

    private:
    Database _db;
    Statement _fetcher;
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

        _fetcher = _db.prepare(`SELECT * FROM words WHERE word = :word`);
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
        mktable ~= ` (id TEXT NOT NULL PRIMARY KEY`;
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
                }
                else static if (isFloatingPoint!(FieldTypes[i]))
                {
                    mktable ~= " REAL";
                }
                else static if (is(FieldTypes[i] == UUID) && field != "id")
                {
                    mktable ~= " TEXT";
                    constraints ~= `FOREIGN KEY (`
                        ~ field
                        ~ `) REFERENCES `
                        ~ field.replace("Id", "s")
                        ~ `(id)`;
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

        tracef("%s create table sql: %s", T.stringof, mktable.data);
        tracef("%s insert sql: %s", T.stringof, insql.data);
        tracef("%s update sql: %s", T.stringof, updsql.data);

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

    T inflateSingle(T)(ref Statement stmt)
    {
        auto results = stmt.execute;
        if (results.empty) return null;
        auto row = results.front;
        return inflate!T(row);
    }

    T inflateMany(T)(ref Statement stmt)
    {
        auto results = stmt.execute;
        if (results.empty) return null;
        return results.map!(x => this.inflate!T(x)).array;
    }
}

