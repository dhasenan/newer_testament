/** Handler for the overall structure of the testament and its books. */
module nt.books;
import jsonizer;

struct Bible
{
    mixin JsonizeMe;
    @jsonize:
    string name;
    Book[] books;
}
struct Book
{
    mixin JsonizeMe;
    @jsonize:
    string name;
    Chapter[] chapters;
}
struct Chapter
{
    mixin JsonizeMe;
    @jsonize:
    uint chapter;
    Verse[] verses;
}
struct Verse
{
    mixin JsonizeMe;
    @jsonize:
    uint verse;
    string text;
}
