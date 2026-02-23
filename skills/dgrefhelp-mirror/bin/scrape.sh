#!/bin/bash
BASE_URL="https://www.rightdecisions.scot.nhs.uk"
OUTPUT_BASE="live_content"

# Standard Categories List
DEFAULT_CATEGORIES=(
    "abnormal-blood-results"
    "admissionsadmission-avoidance"
    "breast"
    "cancer-pathways"
    "cardiology"
    "care-of-the-elderly"
    "chronic-pain"
    "dermatology"
    "dental"
    "diabetes"
    "endocrinology"
    "ent"
    "gastroenterology"
    "general-medicine"
    "general-surgery"
    "haematology"
    "lipid-management"
    "mental-health"
    "musculoskeletal-system"
    "neurology"
    "obstetrics"
    "ophthalmology"
    "orthopaedics"
    "osteoporosis"
    "paediatrics"
    "policies-and-protocols"
    "respiratory"
    "womens-health"
    "urology"
)

scrape_recursive() {
    local url="$1"
    local rel_path="$2"

    if [[ " ${VISITED[@]} " =~ " ${url} " ]]; then return; fi
    VISITED+=("$url")
    echo "  [PROCESS] $url"

    local html=$(curl -s "$url")
    if [ -z "$html" ]; then return; fi

    local is_listing=$(echo "$html" | grep -c "quris-doc-listingPage")
    local title=$(echo "$html" | sed -n 's/.*<h1[^>]*>\(.*\)<\/h1>.*/\1/p' | sed 's/<[^>]*>//g' | head -n 1 | xargs)

    if [ "$is_listing" -gt 0 ]; then
        mkdir -p "$OUTPUT_BASE/$rel_path"
        local current_path=$(echo "$url" | sed "s|$BASE_URL||")
        local sub_links=$(echo "$html" | grep -oE "href=\"${current_path}[^\"]+\"" | cut -d'"' -f2 | sort -u)
        for sub_link in $sub_links; do
            local cleaned_sub=$(echo "$sub_link" | sed 's|/$||')
            local slug=$(basename "$cleaned_sub")
            if [ "$slug" == "$(basename "$current_path")" ]; then continue; fi
            scrape_recursive "${BASE_URL}${cleaned_sub}/" "${rel_path}/${slug}"
        done
    else
        local dir_name=$(dirname "$rel_path")
        mkdir -p "$OUTPUT_BASE/$dir_name"
        local output_file="$OUTPUT_BASE/${rel_path}.md"

        {
            echo "# $title"
            echo ""
            echo "Source: $url"
            echo "Fetched: $(date +%Y-%m-%d)"
            echo ""

            export HTML_CONTENT="$html"
            perl -MHTML::TreeBuilder -MHTML::Entities -0777 -e '
                use strict;
                use warnings;

                my $html = $ENV{HTML_CONTENT} // "";
                my $tree = HTML::TreeBuilder->new;
                $tree->parse_content($html);
                $tree->eof;

                sub clean_text {
                    my ($t) = @_;
                    return "" unless defined $t;
                    decode_entities($t);
                    $t =~ s/\x{00A0}/ /g;
                    $t =~ s/\x{00C2}//g;
                    $t =~ s/\x{FFFD}/ /g;
                    $t =~ s/�/ /g;
                    $t =~ s/\s+/ /g;
                    $t =~ s/^\s+|\s+$//g;
                    return $t;
                }

                sub dedupe_repeated_block {
                    my ($txt) = @_;
                    return $txt unless defined $txt && $txt =~ /\S/;

                    # Remove consecutive duplicate paragraphs/blocks.
                    my @parts = split /\n{2,}/, $txt;
                    my @out;
                    my %seen;
                    for my $p (@parts) {
                        my $norm = $p;
                        $norm =~ s/[ \t]+/ /g;
                        $norm =~ s/^\s+|\s+$//g;
                        next if $norm eq "";
                        next if $seen{$norm}++;
                        push @out, $p;
                    }
                    return join("\n\n", @out) . "\n\n";
                }

                sub inline_md {
                    my ($node) = @_;
                    return "" unless $node;
                    return clean_text($node) unless ref($node);

                    my $tag = lc($node->tag // "");
                    if ($tag eq "br") {
                        return "\n";
                    }

                    my $out = "";
                    for my $c ($node->content_list) {
                        my $seg = inline_md($c);
                        if ($out =~ /[A-Za-z0-9]$/ && $seg =~ /^[A-Za-z0-9]/) {
                            $out .= " ";
                        }
                        $out .= $seg;
                    }

                    if ($tag =~ /^(strong|b)$/) {
                        $out = "**$out**" if $out ne "";
                    } elsif ($tag =~ /^(em|i)$/) {
                        $out = "*$out*" if $out ne "";
                    }
                    return $out;
                }

                sub list_item_chunks {
                    my ($li) = @_;
                    my @chunks;
                    my $buf = "";
                    my @nested;

                    for my $c ($li->content_list) {
                        if (ref($c) && (($c->tag // "") =~ /^(ul|ol)$/i)) {
                            my $text = clean_text($buf);
                            push @chunks, $text if $text ne "";
                            $buf = "";
                            push @nested, $c;
                        } else {
                            my $seg = inline_md($c);
                            if ($seg =~ /\n/) {
                                my @parts = split /\n+/, $seg;
                                for my $i (0..$#parts) {
                                    $buf .= $parts[$i];
                                    if ($i < $#parts) {
                                        my $text = clean_text($buf);
                                        push @chunks, $text if $text ne "";
                                        $buf = "";
                                    }
                                }
                            } else {
                                $buf .= $seg;
                            }
                        }
                    }

                    my $tail = clean_text($buf);
                    push @chunks, $tail if $tail ne "";
                    return (\@chunks, \@nested);
                }

                sub render_list {
                    my ($list, $depth) = @_;
                    my $indent = "    " x $depth;
                    my $md = "";
                    my $last_li_seen = 0;

                    for my $child ($list->content_list) {
                        next unless ref($child);
                        my $tag = lc($child->tag // "");

                        if ($tag eq "li") {
                            my ($chunks, $nested) = list_item_chunks($child);
                            if (@$chunks) {
                                my $first = shift @$chunks;
                                $md .= "$indent- $first\n";
                                for my $extra (@$chunks) {
                                    $md .= "$indent  $extra\n";
                                }
                            } else {
                                $md .= "$indent-\n";
                            }

                            for my $sub (@$nested) {
                                $md .= render_list($sub, $depth + 1);
                            }
                            $last_li_seen = 1;
                        }
                        elsif ($tag =~ /^(ul|ol)$/) {
                            # Malformed CMS pattern: nested list as sibling under same parent list.
                            # Treat as child of the previous <li>.
                            my $sub_depth = $last_li_seen ? $depth + 1 : $depth;
                            $md .= render_list($child, $sub_depth);
                        }
                    }
                    return $md;
                }

                sub render_blocks {
                    my ($root) = @_;
                    my $md = "";

                    for my $child ($root->content_list) {
                        if (!ref($child)) {
                            my $t = clean_text($child);
                            $md .= "$t\n\n" if $t ne "";
                            next;
                        }

                        my $tag = lc($child->tag // "");
                        if ($tag =~ /^h([2-5])$/) {
                            my $lvl = $1 + 1;
                            my $t = clean_text(inline_md($child));
                            $md .= "\n" . ("#" x $lvl) . " $t\n\n" if $t ne "";
                        }
                        elsif ($tag =~ /^(ul|ol)$/) {
                            my $list_md = render_list($child, 0);
                            $md .= "$list_md\n" if $list_md =~ /\S/;
                        }
                        elsif ($tag eq "p") {
                            my $t = clean_text(inline_md($child));
                            $md .= "$t\n\n" if $t ne "";
                        }
                        elsif ($tag eq "div") {
                            my $class = $child->attr("class") // "";
                            next if $class =~ /(govuk-warning-text|EditorialBlock)/i;
                            $md .= render_blocks($child);
                        }
                    }
                    return $md;
                }

                my $primary = $tree->look_down(id => "qrs-grid-primary-content");
                if ($primary) {
                    my $accordion = $primary->look_down(sub {
                        my $n = shift;
                        return 0 unless ref($n);
                        return 0 unless (($n->tag // "") eq "div");
                        my $c = $n->attr("class") // "";
                        return $c =~ /govuk-accordion/;
                    });

                    if ($accordion) {
                        my $pre = HTML::Element->new("div");
                        for my $c ($primary->content_list) {
                            last if ref($c) && $c == $accordion;
                            $pre->push_content($c->clone);
                        }
                        my $pre_md = render_blocks($pre);
                        $pre_md = dedupe_repeated_block($pre_md);
                        if ($pre_md =~ /\w/) {
                            print "## Overview\n\n$pre_md";
                        }

                        my @sections = $accordion->look_down(sub {
                            my $n = shift;
                            return 0 unless ref($n);
                            return 0 unless (($n->tag // "") eq "div");
                            my $c = $n->attr("class") // "";
                            my %cls = map { $_ => 1 } grep { $_ ne "" } split /\s+/, $c;
                            return $cls{"govuk-accordion__section"} ? 1 : 0;
                        });

                        my %seen_titles;
                        for my $sec (@sections) {
                            my $title_el = $sec->look_down(sub {
                                my $n = shift;
                                return 0 unless ref($n);
                                my $c = $n->attr("class") // "";
                                return $c =~ /govuk-accordion__section-button/;
                            });
                            my $content_el = $sec->look_down(sub {
                                my $n = shift;
                                return 0 unless ref($n);
                                my $c = $n->attr("class") // "";
                                return $c =~ /govuk-accordion__section-content/;
                            });
                            next unless $content_el;

                            my $title = $title_el ? clean_text(inline_md($title_el)) : "";
                            next if $title ne "" && $seen_titles{$title}++;
                            if ($title ne "") {
                                print "## $title\n\n";
                            }
                            my $section_md = render_blocks($content_el);
                            $section_md = dedupe_repeated_block($section_md);
                            print $section_md;
                        }
                    } else {
                        print render_blocks($primary);
                    }
                }

                my $editorial = $tree->look_down(id => "EditorialBlock");
                if ($editorial) {
                    print "---\n## Editorial Information\n\n";
                    for my $p ($editorial->look_down(_tag => "p")) {
                        my @strong = $p->look_down(_tag => qr/^(strong|b)$/i);
                        if (@strong) {
                            my $label = clean_text($strong[0]->as_text // "");
                            $label =~ s/:\s*$//;
                            my $raw = $p->as_text;
                            decode_entities($raw);
                            $raw =~ s/\x{00A0}/ /g;
                            $raw =~ s/\x{00C2}//g;
                            $raw =~ s/^\s+|\s+$//g;
                            $raw =~ s/^\Q$label\E:?\s*//i;
                            my $value = clean_text($raw);
                            print "- **$label:** $value\n" if $label ne "";
                        } else {
                            my $txt = clean_text(inline_md($p));
                            print "- $txt\n" if ($txt ne "" && $txt !~ /Editorial Information/i);
                        }
                    }
                }

                $tree->delete;
            '
        } > "$output_file"
        sleep 0.1
    fi
}

CATEGORIES=("${@:-${DEFAULT_CATEGORIES[@]}}")
VISITED=()
for CAT in "${CATEGORIES[@]}"; do
    scrape_recursive "${BASE_URL}/dgrefhelp-nhs-dumfries-galloway/${CAT}/" "$CAT"
done
