#!/usr/bin/env python3
import sys
import os
import re
import datetime
import urllib.parse
import subprocess

def slugify(text):
    text = text.lower()
    text = re.sub(r'[^a-z0-9\s-]', '', text)
    text = re.sub(r'[\s-]+', '-', text).strip('-')
    return text or "document"

def inline_styles(text):
    # Escape HTML to prevent injection
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    
    # Bold **text**
    text = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', text)
    # Italic *text*
    text = re.sub(r'\*(.*?)\*', r'<em>\1</em>', text)
    # Italic _text_
    text = re.sub(r'_(.*?)_', r'<em>\1</em>', text)
    # Inline code `code`
    text = re.sub(r'`(.*?)`', r'<code class="inline-code">\1</code>', text)
    # Links [text](url)
    text = re.sub(r'\[(.*?)\]\((.*?)\)', r'<a href="\2" target="_blank">\1</a>', text)
    
    return text

def markdown_to_html(md_text):
    lines = md_text.splitlines()
    html_lines = []
    
    in_code_block = False
    code_lang = ""
    code_content = []
    
    in_list = None  # 'ul', 'ol', or None
    in_blockquote = False
    blockquote_content = []
    
    def close_list():
        nonlocal in_list
        if in_list:
            html_lines.append(f"</{in_list}>")
            in_list = None
            
    def close_blockquote():
        nonlocal in_blockquote, blockquote_content
        if in_blockquote:
            body = markdown_to_html("\n".join(blockquote_content))
            html_lines.append(f"<blockquote>{body}</blockquote>")
            blockquote_content = []
            in_blockquote = False

    for line in lines:
        stripped = line.strip()
        
        # Handle code blocks
        if stripped.startswith("```"):
            close_list()
            close_blockquote()
            if in_code_block:
                code_text = "\n".join(code_content)
                code_html = code_text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                html_lines.append(
                    f'<div class="code-container">'
                    f'  <div class="code-header">'
                    f'    <span class="code-lang">{code_lang or "code"}</span>'
                    f'    <button class="copy-btn" onclick="copyCode(this)">Copy</button>'
                    f'  </div>'
                    f'  <pre><code class="language-{code_lang}">{code_html}</code></pre>'
                    f'</div>'
                )
                in_code_block = False
                code_content = []
            else:
                in_code_block = True
                code_lang = stripped[3:].strip()
            continue
            
        if in_code_block:
            code_content.append(line)
            continue
            
        # Handle blank lines
        if not stripped:
            close_list()
            close_blockquote()
            continue
            
        # Blockquotes
        if stripped.startswith(">"):
            close_list()
            in_blockquote = True
            bq_line = line.lstrip()[1:]
            if bq_line.startswith(" "):
                bq_line = bq_line[1:]
            blockquote_content.append(bq_line)
            continue
        else:
            close_blockquote()
            
        # Headings
        if stripped.startswith("#"):
            close_list()
            parts = stripped.split(" ", 1)
            level = len(parts[0])
            if 1 <= level <= 6 and len(parts) > 1:
                title_text = parts[1]
                slug = slugify(title_text)
                html_lines.append(f'<h{level} id="{slug}">{inline_styles(title_text)}</h{level}>')
                continue
                
        # Horizontal rule
        if stripped in ["---", "***", "___"]:
            close_list()
            html_lines.append("<hr>")
            continue
            
        # Unordered list item
        if stripped.startswith("- ") or stripped.startswith("* ") or stripped.startswith("• "):
            if in_list != 'ul':
                close_list()
                html_lines.append("<ul>")
                in_list = 'ul'
            item_text = stripped[2:].strip()
            html_lines.append(f"<li>{inline_styles(item_text)}</li>")
            continue
            
        # Ordered list item
        ol_match = re.match(r'^(\d+)\.\s+(.*)$', stripped)
        if ol_match:
            if in_list != 'ol':
                close_list()
                html_lines.append("<ol>")
                in_list = 'ol'
            item_text = ol_match.group(2).strip()
            html_lines.append(f"<li>{inline_styles(item_text)}</li>")
            continue
            
        # Normal paragraph
        close_list()
        html_lines.append(f"<p>{inline_styles(line)}</p>")
        
    close_list()
    close_blockquote()
    
    return "\n".join(html_lines)

def build_html_document(title, content_md):
    body_content = markdown_to_html(content_md)
    date_str = datetime.date.today().strftime("%B %d, %Y")
    
    # Calculate word count & read time
    words = len(content_md.split())
    read_time = max(1, round(words / 200))
    
    # Premium glassmorphic template
    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root {{
            --font-body: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            --font-heading: 'Outfit', var(--font-body);
            
            /* Obsidian Dark Theme */
            --bg-app: #080c14;
            --bg-canvas: #0c1220;
            --bg-card: rgba(17, 24, 39, 0.55);
            --bg-card-hover: rgba(24, 32, 51, 0.7);
            --text-primary: #f3f4f6;
            --text-secondary: #9ca3af;
            --text-muted: #6b7280;
            --color-accent: #6366f1;
            --color-accent-light: #818cf8;
            --color-accent-glow: rgba(99, 102, 241, 0.15);
            --border-color: rgba(255, 255, 255, 0.07);
            --code-bg: #0f1422;
            --code-header-bg: #070a12;
            --quote-bg: rgba(99, 102, 241, 0.05);
            --shadow-premium: 0 20px 40px -15px rgba(0, 0, 0, 0.5);
            --scrollbar-thumb: #1e293b;
        }}

        .light-theme {{
            /* Clean Minimalist Light Theme */
            --bg-app: #f5f7fb;
            --bg-canvas: #ffffff;
            --bg-card: rgba(255, 255, 255, 0.8);
            --bg-card-hover: rgba(255, 255, 255, 0.95);
            --text-primary: #111827;
            --text-secondary: #4b5563;
            --text-muted: #9ca3af;
            --color-accent: #4f46e5;
            --color-accent-light: #6366f1;
            --color-accent-glow: rgba(79, 70, 229, 0.08);
            --border-color: rgba(0, 0, 0, 0.08);
            --code-bg: #f3f4f6;
            --code-header-bg: #e5e7eb;
            --quote-bg: rgba(79, 70, 229, 0.03);
            --shadow-premium: 0 20px 40px -15px rgba(0, 0, 0, 0.05);
            --scrollbar-thumb: #cbd5e1;
        }}

        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }}

        body {{
            background-color: var(--bg-app);
            color: var(--text-primary);
            font-family: var(--font-body);
            line-height: 1.7;
            -webkit-font-smoothing: antialiased;
            transition: background-color 0.4s ease, color 0.4s ease;
            min-height: 100vh;
            overflow-x: hidden;
        }}

        /* Subtle ambient glow backdrops in dark mode */
        body::before {{
            content: '';
            position: fixed;
            top: -10%;
            left: 50%;
            transform: translateX(-50%);
            width: 80vw;
            height: 50vh;
            background: radial-gradient(circle, var(--color-accent-glow) 0%, transparent 70%);
            z-index: -1;
            pointer-events: none;
            transition: opacity 0.4s ease;
        }}

        .light-theme::before {{
            opacity: 0.5;
        }}

        header {{
            position: sticky;
            top: 0;
            width: 100%;
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            background: rgba(var(--bg-app), 0.7);
            border-bottom: 1px solid var(--border-color);
            z-index: 100;
            transition: border-color 0.4s ease;
        }}

        .header-container {{
            max-width: 1100px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 1rem 2rem;
        }}

        .logo {{
            font-family: var(--font-heading);
            font-weight: 800;
            font-size: 1.25rem;
            letter-spacing: -0.5px;
            background: linear-gradient(135deg, var(--color-accent-light), var(--color-accent));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }}

        .actions-group {{
            display: flex;
            gap: 0.75rem;
            align-items: center;
        }}

        .btn {{
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            padding: 0.5rem 1rem;
            border-radius: 9999px;
            font-size: 0.875rem;
            font-weight: 500;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            backdrop-filter: blur(8px);
        }}

        .btn:hover {{
            background: var(--bg-card-hover);
            transform: translateY(-1px);
            border-color: var(--color-accent);
            box-shadow: 0 4px 12px var(--color-accent-glow);
        }}

        .btn-primary {{
            background: var(--color-accent);
            color: #ffffff;
            border-color: var(--color-accent);
        }}

        .btn-primary:hover {{
            background: var(--color-accent-light);
            border-color: var(--color-accent-light);
            box-shadow: 0 4px 16px rgba(99, 102, 241, 0.4);
        }}

        .main-layout {{
            max-width: 1100px;
            margin: 2.5rem auto;
            padding: 0 2rem;
            display: grid;
            grid-template-columns: 260px 1fr;
            gap: 3rem;
        }}

        /* Table of Contents / Sidebar */
        .sidebar {{
            position: sticky;
            top: 6rem;
            height: calc(100vh - 10rem);
            overflow-y: auto;
            padding-right: 0.5rem;
        }}

        .sidebar::-webkit-scrollbar {{
            width: 4px;
        }}
        .sidebar::-webkit-scrollbar-thumb {{
            background: var(--scrollbar-thumb);
            border-radius: 10px;
        }}

        .toc-title {{
            font-family: var(--font-heading);
            font-weight: 700;
            font-size: 0.875rem;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: var(--text-muted);
            margin-bottom: 1rem;
        }}

        .toc-list {{
            list-style: none;
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
        }}

        .toc-link {{
            color: var(--text-secondary);
            text-decoration: none;
            font-size: 0.9rem;
            display: block;
            padding: 0.35rem 0.75rem;
            border-left: 2px solid transparent;
            transition: all 0.2s ease;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }}

        .toc-link:hover {{
            color: var(--color-accent-light);
            border-left-color: var(--color-accent-light);
            padding-left: 0.9rem;
        }}

        .toc-link.active {{
            color: var(--color-accent);
            font-weight: 600;
            border-left-color: var(--color-accent);
            background: var(--color-accent-glow);
            border-radius: 0 8px 8px 0;
        }}

        /* Main Document Sheet */
        .document-wrapper {{
            min-width: 0; /* Prevents overflow in grid items */
        }}

        .document-card {{
            background: var(--bg-card);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--border-color);
            border-radius: 1.5rem;
            padding: 3rem;
            box-shadow: var(--shadow-premium);
            transition: background-color 0.4s ease, border-color 0.4s ease;
        }}

        .doc-meta {{
            display: flex;
            flex-wrap: wrap;
            gap: 1.5rem;
            color: var(--text-muted);
            font-size: 0.875rem;
            font-weight: 500;
            margin-bottom: 1.5rem;
            align-items: center;
        }}

        .meta-item {{
            display: flex;
            align-items: center;
            gap: 0.35rem;
        }}

        .doc-title {{
            font-family: var(--font-heading);
            font-weight: 800;
            font-size: 2.5rem;
            line-height: 1.25;
            margin-bottom: 2rem;
            letter-spacing: -1px;
            background: linear-gradient(135deg, var(--text-primary) 30%, var(--text-secondary) 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }}

        .light-theme .doc-title {{
            background: none;
            -webkit-text-fill-color: initial;
            color: var(--text-primary);
        }}

        /* Rich Text Formatting */
        .doc-body {{
            font-size: 1.05rem;
            color: var(--text-secondary);
        }}

        .doc-body p {{
            margin-bottom: 1.5rem;
        }}

        .doc-body h1, .doc-body h2, .doc-body h3, .doc-body h4, .doc-body h5, .doc-body h6 {{
            font-family: var(--font-heading);
            color: var(--text-primary);
            font-weight: 700;
            margin-top: 2.25rem;
            margin-bottom: 1rem;
            line-height: 1.3;
            letter-spacing: -0.5px;
        }}

        .doc-body h1 {{ font-size: 1.85rem; border-bottom: 1px solid var(--border-color); padding-bottom: 0.5rem; }}
        .doc-body h2 {{ font-size: 1.5rem; }}
        .doc-body h3 {{ font-size: 1.25rem; }}

        .doc-body a {{
            color: var(--color-accent);
            text-decoration: none;
            border-bottom: 1px solid transparent;
            transition: all 0.2s ease;
        }}

        .doc-body a:hover {{
            color: var(--color-accent-light);
            border-bottom-color: var(--color-accent-light);
        }}

        .doc-body ul, .doc-body ol {{
            margin-bottom: 1.5rem;
            padding-left: 1.75rem;
        }}

        .doc-body li {{
            margin-bottom: 0.5rem;
        }}

        .doc-body blockquote {{
            background: var(--quote-bg);
            border-left: 4px solid var(--color-accent);
            padding: 1rem 1.5rem;
            margin: 1.5rem 0;
            border-radius: 0 12px 12px 0;
            font-style: italic;
        }}

        .doc-body blockquote p:last-child {{
            margin-bottom: 0;
        }}

        .doc-body hr {{
            border: 0;
            height: 1px;
            background: var(--border-color);
            margin: 2.5rem 0;
        }}

        /* Code Block Styling */
        .code-container {{
            border: 1px solid var(--border-color);
            border-radius: 12px;
            overflow: hidden;
            margin: 1.75rem 0;
            box-shadow: 0 4px 20px -5px rgba(0,0,0,0.3);
        }}

        .code-header {{
            background: var(--code-header-bg);
            padding: 0.5rem 1rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border-color);
        }}

        .code-lang {{
            font-size: 0.75rem;
            font-family: var(--font-heading);
            font-weight: 700;
            text-transform: uppercase;
            color: var(--text-muted);
            letter-spacing: 0.5px;
        }}

        .copy-btn {{
            background: transparent;
            border: 1px solid var(--border-color);
            color: var(--text-secondary);
            padding: 0.25rem 0.6rem;
            font-size: 0.75rem;
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.2s ease;
        }}

        .copy-btn:hover {{
            background: var(--bg-card-hover);
            border-color: var(--color-accent);
            color: var(--text-primary);
        }}

        .doc-body pre {{
            margin: 0;
            background: var(--code-bg);
            padding: 1.25rem;
            overflow-x: auto;
        }}

        .doc-body code {{
            font-family: 'Courier New', Courier, monospace;
            font-size: 0.9rem;
        }}

        .inline-code {{
            background: var(--code-bg);
            color: var(--color-accent-light);
            padding: 0.15rem 0.4rem;
            border-radius: 6px;
            font-family: 'Courier New', Courier, monospace;
            font-size: 0.9rem;
            border: 1px solid var(--border-color);
        }}

        .light-theme .inline-code {{
            color: var(--color-accent);
        }}

        /* Responsive Layout */
        @media (max-width: 850px) {{
            .main-layout {{
                grid-template-columns: 1fr;
                gap: 2rem;
            }}
            .sidebar {{
                display: none;
            }}
            .document-card {{
                padding: 1.75rem;
            }}
        }}

        /* Print styles */
        @media print {{
            header, .sidebar, .copy-btn, .btn {{
                display: none !important;
            }}
            body {{
                background: #ffffff !important;
                color: #000000 !important;
            }}
            .document-card {{
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
                background: transparent !important;
            }}
            .doc-title {{
                color: #000000 !important;
                background: none !important;
                -webkit-text-fill-color: initial !important;
            }}
        }}
    </style>
</head>
<body>
    <header>
        <div class="header-container">
            <div class="logo">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-file-text"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>
                QuickShell Doc
            </div>
            <div class="actions-group">
                <button class="btn" onclick="toggleTheme()" id="themeBtn">
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-sun"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg>
                    Theme
                </button>
                <button class="btn" onclick="window.print()">
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-printer"><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 9V3a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v6"/><rect x="6" y="14" width="12" height="8" rx="1"/></svg>
                    Print
                </button>
                <button class="btn btn-primary" onclick="copyDocumentMarkdown()">
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-copy"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
                    Copy MD
                </button>
            </div>
        </div>
    </header>

    <div class="main-layout">
        <aside class="sidebar">
            <div class="toc-title">On this page</div>
            <nav>
                <ul class="toc-list" id="tocList">
                    <!-- Table of contents will be auto-generated here -->
                </ul>
            </nav>
        </aside>

        <main class="document-wrapper">
            <article class="document-card">
                <div class="doc-meta">
                    <div class="meta-item">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-calendar"><path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/></svg>
                        {date_str}
                    </div>
                    <div class="meta-item">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-clock"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                        {read_time} min read
                    </div>
                    <div class="meta-item">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-file"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/></svg>
                        {words} words
                    </div>
                </div>

                <h1 class="doc-title">{title}</h1>

                <div class="doc-body">
                    {body_content}
                </div>
            </article>
        </main>
    </div>

    <!-- Raw markdown hidden for copy function -->
    <textarea id="rawMarkdown" style="display:none;">{content_md}</textarea>

    <script>
        // Set initial theme
        if (localStorage.getItem('theme') === 'light' || 
            (!localStorage.getItem('theme') && window.matchMedia('(prefers-color-scheme: light)').matches)) {{
            document.documentElement.classList.add('light-theme');
        }}

        function toggleTheme() {{
            const isLight = document.documentElement.classList.toggle('light-theme');
            localStorage.setItem('theme', isLight ? 'light' : 'dark');
        }}

        function copyCode(btn) {{
            const pre = btn.parentElement.nextElementSibling;
            const code = pre.querySelector('code');
            
            navigator.clipboard.writeText(code.innerText).then(() => {{
                const originalText = btn.innerText;
                btn.innerText = 'Copied!';
                btn.style.borderColor = 'var(--color-accent)';
                btn.style.color = 'var(--color-accent)';
                setTimeout(() => {{
                    btn.innerText = originalText;
                    btn.style.borderColor = '';
                    btn.style.color = '';
                }}, 2000);
            }}).catch(err => {{
                console.error('Could not copy text: ', err);
            }});
        }}

        function copyDocumentMarkdown() {{
            const mdText = document.getElementById('rawMarkdown').value;
            navigator.clipboard.writeText(mdText).then(() => {{
                alert('Document markdown copied to clipboard!');
            }}).catch(err => {{
                console.error('Could not copy markdown: ', err);
            }});
        }}

        // Dynamic Table of Contents Generation
        document.addEventListener('DOMContentLoaded', () => {{
            const headings = document.querySelectorAll('.doc-body h1, .doc-body h2, .doc-body h3');
            const tocList = document.getElementById('tocList');
            
            if (headings.length === 0) {{
                document.querySelector('.sidebar').style.display = 'none';
                document.querySelector('.main-layout').style.gridTemplateColumns = '1fr';
                return;
            }}

            const headingArray = [];
            headings.forEach((heading) => {{
                // Fallback ID if not present
                if (!heading.id) {{
                    heading.id = heading.innerText.toLowerCase().replace(/[^a-z0-9]+/g, '-');
                }}
                
                const li = document.createElement('li');
                const a = document.createElement('a');
                a.href = '#' + heading.id;
                a.className = 'toc-link';
                a.innerText = heading.innerText;
                
                // Add nesting class based on tag name
                if (heading.tagName === 'H2') {{
                    a.style.paddingLeft = '1.5rem';
                }} else if (heading.tagName === 'H3') {{
                    a.style.paddingLeft = '2.25rem';
                }}
                
                li.appendChild(a);
                tocList.appendChild(li);
                
                headingArray.push({{
                    element: heading,
                    link: a
                }});
            }});

            // Active header tracking on scroll
            function trackActiveHeader() {{
                const scrollPos = window.scrollY + 120;
                let activeIndex = -1;
                
                for (let i = 0; i < headingArray.length; i++) {{
                    if (headingArray[i].element.offsetTop <= scrollPos) {{
                        activeIndex = i;
                    }} else {{
                        break;
                    }}
                }}
                
                headingArray.forEach((h, idx) => {{
                    if (idx === activeIndex) {{
                        h.link.classList.add('active');
                    }} else {{
                        h.link.classList.remove('active');
                    }}
                }});
            }}

            window.addEventListener('scroll', trackActiveHeader);
            trackActiveHeader(); // Initial call
        }});
    </script>
</body>
</html>
"""
    return html_template

def main():
    if len(sys.argv) < 3:
        print("Error: Title and Content arguments are required.")
        sys.exit(1)

    title = sys.argv[1]
    content = sys.argv[2]
    
    # Try to verify if there's any Google authentication token to perform upload
    google_uploaded = False
    gdocs_token_path = os.path.expanduser("~/.config/quickshell/google_docs_token.json")
    
    # Standard placeholder for Google Docs authentication flow checking
    if os.path.exists(gdocs_token_path):
        try:
            from googleapiclient.discovery import build
            from google.oauth2.credentials import Credentials
            
            creds = Credentials.from_authorized_user_file(gdocs_token_path)
            if creds and creds.valid:
                service = build('docs', 'v1', credentials=creds)
                
                # Google Docs API requires specific document creation format.
                # Since the API creates a blank document and then populates it,
                # we do the initial create call here.
                doc = service.documents().create(body={"title": title}).execute()
                doc_id = doc.get("documentId")
                
                # Simple markdown-to-docs requests structure.
                # For basic implementation, we just insert the content.
                requests = [
                    {
                        'insertText': {
                            'location': {
                                'index': 1,
                            },
                            'text': content
                        }
                    }
                ]
                service.documents().batchUpdate(documentId=doc_id, body={'requests': requests}).execute()
                
                print(f"Successfully created Google Doc! Title: '{title}'")
                print(f"Document ID: {doc_id}")
                print(f"URL: https://docs.google.com/document/d/{doc_id}/edit")
                google_uploaded = True
        except Exception as e:
            # Fallback gracefully
            print(f"Google Docs API Upload failed or library missing: {e}. Falling back to premium local HTML document...")
    
    if not google_uploaded:
        # Fallback: Save beautifully rendered local HTML file in ~/Documents
        docs_dir = os.path.expanduser("~/Documents")
        if not os.path.exists(docs_dir):
            try:
                os.makedirs(docs_dir, exist_ok=True)
            except Exception:
                docs_dir = os.path.expanduser("~") # Fallback to home dir
                
        slug = slugify(title)
        filename = f"{slug}.html"
        filepath = os.path.join(docs_dir, filename)
        
        try:
            html_content = build_html_document(title, content)
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(html_content)
                
            print(f"--- Document Created Successfully ---")
            print(f"Location: {filepath}")
            print(f"A premium interactive local HTML document has been created.")
            print(f"Opening the document now...")
            
            # Open with user's default browser or handler
            subprocess.Popen(["xdg-open", filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
        except Exception as e:
            print(f"Error creating local HTML document: {e}")
            sys.exit(1)

if __name__ == "__main__":
    main()
