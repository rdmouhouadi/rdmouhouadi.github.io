# Richie Mouhouadi | Portfolio

![Site checks](https://github.com/rdmouhouadi/rdmouhouadi.github.io/actions/workflows/checks.yml/badge.svg)

Live site: **https://rdmouhouadi.github.io**

The personal site of a former reservoir engineer turned data scientist and ML engineer, with a sweet spot for MLOps. It is a **technical website built in an editorial style**: it reads like a magazine feature, while the engineering underneath is checked automatically on every change.

## The editorial side

The site tells a career change as a story instead of listing skills.

- An oversized serif headline opens the page, followed by a short "Hello" block with a photo and links.
- A story section with a drop cap, a pull quote, and three chapters: Then, Now, Next.
- Projects are laid out like a magazine contents page: big titles, one plain sentence each, then the stack.
- Typography carries the personality: **Instrument Serif** for display and **Hanken Grotesk** for text.
- Light and dark themes share one palette: pale sage paper, ink, and a single blue accent.

Deep technical detail lives in each project's repository README, so the page stays easy to read. Work done inside companies, where the code is private, is told as short case studies: context, problem, methodology, results, takeaway.

## The technical side

- **Static and dependency-free.** One self-contained `index.html` with inline CSS and a few lines of JavaScript. No framework, no build step. Only Google Fonts load from outside.
- **Light and dark mode.** Follows the visitor's system setting, with a toggle that remembers the choice.
- **Responsive and accessible.** Works from phone to desktop, with visible keyboard focus, semantic landmarks, and reduced motion respected.
- **Search and sharing.** Open Graph preview image, favicon, canonical URL, JSON-LD `Person` data, `sitemap.xml`, and `robots.txt`.
- **Privacy-friendly stats.** Optional [GoatCounter](https://www.goatcounter.com), with no cookies.

## Automated checks

A GitHub Actions workflow (`.github/workflows/checks.yml`) runs on every push, on pull requests, and weekly:

| Check | Tool | Fails when |
| --- | --- | --- |
| HTML validity | html-validate | markup or accessibility rules are broken |
| External links | lychee | a link stops working |
| Quality scores | Lighthouse CI | accessibility or SEO drop below 95 (performance and best practices warn below 90) |

## Repository layout

```
index.html                  the whole site
og-image.png                link preview image
images/                     project screenshots
case-studies/               write-ups of company projects
resume.pdf                  CV download
sitemap.xml, robots.txt     search engine files
lighthouserc.json           Lighthouse thresholds
.htmlvalidate.json          HTML validation rules
.github/workflows/          automated checks
```

## Run it locally

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Deployment

Hosted on GitHub Pages from the `main` branch. Pushing a change publishes it.

## Reuse

You are welcome to take inspiration from the structure and code. Please write your own content and use your own photo.
