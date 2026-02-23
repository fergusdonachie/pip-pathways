# DGRefHelp Mirroring Skill

Automates the high-fidelity extraction of clinical pathways from the Right Decision Service (RDS) CMS into a clean, hierarchical Markdown repository.

## Capabilities

- **Recursive Crawling:** Drills down from category listing pages into individual clinical topics.
- **High-Fidelity Markdown:** 
    - Enforces rigid 4-space nesting for clinical bullets (GitHub compatibility).
    - Captures "Overview" content often missed by standard scrapers (e.g., qFIT tables, intro protocols).
    - Preserves bold/italic formatting and sub-headers.
- **Boilerplate Removal:** Strips site-wide warnings, navigation, and terms of use to keep files clinical.
- **Editorial Sync:** Standardizes author and review metadata into clean markdown lists.

## Usage

### Process specific categories
\`\`\`bash
bash bin/scrape.sh cardiology womens-health
\`\`\`

### Process everything (Bulk)
\`\`\`bash
bash bin/scrape.sh
\`\`\`

### Sync to GitHub
After scraping, commit and push from the \`github_sync\` folder:
\`\`\`bash
cd github_sync
cp -r ../live_content/* live_content/
git add .
git commit -m "Sync DGRefHelp content"
git push origin main
\`\`\`

## Maintenance

The scraping logic is contained in \`bin/scrape.sh\`. It uses a Perl-based tokenizing parser to handle non-standard HTML structures commonly output by the RDS CMS.
