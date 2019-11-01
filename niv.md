# NIV Bible

This will be a bit more approachable than the KJV. Maybe not as silly, though.

https://www.biblestudytools.com/niv/ has the entire text available.

Links to the individual books:

    div#testament-O a
    div#testament-N a

A book URL will look like https://www.biblestudytools.com/1-corinthians/ and contains chapter links:

    div.panel-body a

The individual chapter URL will look like https://www.biblestudytools.com/1-corinthians/14.html and
contains a full text in

    div.scripture

Within that div, there are `<h2>` headings and `<div class="verse">` verses. A verse's structure is:

    <span class="verse-number">2</span>
    <span class="verse-2">
        Verse text<sup class="verse-footnote">footnote link</sup> more verse text
    </span>

Putting it all together, we have:

    <div class="scripture">
      <h2>The Sermon in the Valley</h2>
      <div id="v-1" class="verse">
        <span class="verse-number">1</span>
        <span class="verse-1">
            Verse text<sup class="verse-footnote">footnote link</sup>
            more verse text
        </span>
      </div>
      <div id="v-2" class="verse">
        <span class="verse-number">2</span>
        <span class="verse-2">
            Verse text<sup class="verse-footnote">footnote link</sup>
            more verse text
        </span>
      </div>
    </div>

That means we can pretty much go:

    events ~= Event.StartChapter;
    foreach (s; document.querySelector("div.scripture").children)
    {
        auto e = cast(Element)s;
        if (!e) continue;
        switch (e.tagName)
        {
            case "h2":
                events ~= Event.NewSection(e.innerText);
                break;
            case "div":
                events ~= Event.Verse(e.querySelectorAll("span")[1].directText);
                break;
            default:
                break;
        }
    }
    events ~= Event.EndChapter;

Then, to build the Markov model
