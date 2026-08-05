import React, { useMemo, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import hljs from "highlight.js/lib/common";
import { CopyIcon, CheckIcon } from "./Icons.jsx";

function CodeBlock({ lang, code }) {
  const [copied, setCopied] = useState(false);
  const html = useMemo(() => {
    try {
      if (lang && hljs.getLanguage(lang)) {
        return hljs.highlight(code, { language: lang }).value;
      }
      return hljs.highlightAuto(code).value;
    } catch {
      return null;
    }
  }, [lang, code]);

  const copy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };

  return (
    <div className="codeblock">
      <div className="codeblock-head">
        <span>{lang || "code"}</span>
        <button className="copy-code" onClick={copy}>
          {copied ? <CheckIcon size={13} /> : <CopyIcon size={13} />}
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      <pre>
        {html != null ? (
          <code dangerouslySetInnerHTML={{ __html: html }} />
        ) : (
          <code>{code}</code>
        )}
      </pre>
    </div>
  );
}

function openExternal(href) {
  if (window.__TAURI_INTERNALS__) {
    import("@tauri-apps/plugin-opener").then(({ openUrl }) => openUrl(href));
  } else {
    window.open(href, "_blank", "noopener");
  }
}

const components = {
  a: ({ href, children }) => (
    <a
      href={href}
      onClick={(e) => {
        e.preventDefault();
        if (href) openExternal(href);
      }}
    >
      {children}
    </a>
  ),
  table: ({ children }) => (
    <div className="tbl-wrap">
      <table>{children}</table>
    </div>
  ),
  code: ({ inline, className, children }) => {
    const text = String(children ?? "");
    const langMatch = /language-(\w+)/.exec(className || "");
    // react-markdown v9: block code arrives wrapped in <pre>; detect by newline/lang
    if (inline || (!langMatch && !text.includes("\n"))) {
      return <code className="inline">{text}</code>;
    }
    return <CodeBlock lang={langMatch ? langMatch[1] : ""} code={text.replace(/\n$/, "")} />;
  },
  pre: ({ children }) => <>{children}</>,
};

export default function Markdown({ text }) {
  return (
    <div className="md">
      <ReactMarkdown
        remarkPlugins={[remarkGfm, remarkMath]}
        rehypePlugins={[rehypeKatex]}
        components={components}
      >
        {text}
      </ReactMarkdown>
    </div>
  );
}
