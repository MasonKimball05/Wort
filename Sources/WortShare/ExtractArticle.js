// Runs in the page when a Safari page is shared to Wort. Hands back the page
// title, the selection (if any) and the article's paragraphs: the <p> elements
// inside <article> (or <main>, or the page), skipping short ones like captions
// and buttons. Read-only: it changes nothing on the page.
var ExtractArticle = function() {};
ExtractArticle.prototype = {
    run: function(args) {
        var root = document.querySelector("article") || document.querySelector("main") || document.body;
        var paragraphs = Array.prototype.slice.call(root.querySelectorAll("p"))
            .map(function(p) { return (p.innerText || "").replace(/\s+/g, " ").trim(); })
            .filter(function(t) { return t.split(" ").length >= 6; });
        args.completionFunction({
            title: document.title || "",
            url: document.URL || "",
            selection: (window.getSelection ? window.getSelection().toString() : "") || "",
            text: paragraphs.join("\n\n")
        });
    },
    finalize: function(args) {}
};
var ExtensionPreprocessingJS = new ExtractArticle;
