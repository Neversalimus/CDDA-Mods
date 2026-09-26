param([string]$Source0910)
$ErrorActionPreference="Stop"
function Write-Utf8NoBom([string]$Path,[string]$Text) {
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function Hash-File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Name) {
    $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) {
        throw "$Name expected once, found $count"
    }
    return $Text.Replace($Old,$New)
}

function Replace-CppRange([string]$Text,[string]$Start,[string]$End,[string]$Replacement,[string]$Name) {
    $a = $Text.IndexOf($Start)
    if ($a -lt 0) { throw "$Name start marker missing: $Start" }
    $b = $Text.IndexOf($End,$a)
    if ($b -le $a) { throw "$Name end marker missing: $End" }
    return $Text.Substring(0,$a) + $Replacement + "`n`n" + $Text.Substring($b)
}

$spPath = Join-Path $Source0910 "src\survivor_progression.cpp"
$sp = [IO.File]::ReadAllText($spPath)

$sp = $sp.Replace('"0.9.9"','"0.9.10"')
$sp = $sp.Replace("Survivor Progression v0.9.9","Survivor Progression v0.9.10")
$sp = $sp.Replace("Survivor Progression 0.9.9 initialized:","Survivor Progression 0.9.10 initialized:")

$rankHelpers = @'
bool ranked_perk_id( const perk_def &perk )
{
    const std::string id = perk.id ? perk.id : "";
    return id == "c_conditioning" || id == "s_field" || id == "m_light" ||
           id == "f_hands" || id == "g_route" || id == "a_adapt";
}

int perk_max_rank( const perk_def &perk )
{
    const std::string id = perk.id ? perk.id : "";
    if( id == "s_field" || id == "g_route" ) {
        return 3;
    }
    if( id == "c_conditioning" || id == "m_light" ||
        id == "f_hands" || id == "a_adapt" ) {
        return 5;
    }
    return 1;
}

double perk_extra_rank_scale( const perk_def &perk )
{
    const std::string id = perk.id ? perk.id : "";
    if( id == "c_conditioning" ) return 0.125;       // +8% -> +12% at V
    if( id == "s_field" ) return 0.50;               // +10% -> +20% at III
    if( id == "m_light" ) return 1.0 / 6.0;          // -3% -> -5% at V
    if( id == "f_hands" ) return 0.40;               // +5% -> +13% at V
    if( id == "g_route" ) return 1.0 / 3.0;          // -3% -> -5% at III
    if( id == "a_adapt" ) return 0.20;               // +25% -> +45% at V
    return 0.0;
}

int perk_rank( const perk_def &perk )
{
    return static_cast<int>( std::max<int64_t>(
        0, std::min<int64_t>( perk_max_rank( perk ), get_state( perk_key( perk ), 0 ) ) ) );
}

bool perk_maxed( const perk_def &perk )
{
    return perk_rank( perk ) >= perk_max_rank( perk );
}

double perk_rank_multiplier_for( const perk_def &perk, int rank )
{
    if( rank <= 0 ) {
        return 0.0;
    }
    rank = std::min( rank, perk_max_rank( perk ) );
    return 1.0 + static_cast<double>( rank - 1 ) * perk_extra_rank_scale( perk );
}

double perk_rank_multiplier( const perk_def &perk )
{
    return perk_rank_multiplier_for( perk, perk_rank( perk ) );
}

std::string rank_roman( int rank )
{
    switch( rank ) {
        case 1: return "I";
        case 2: return "II";
        case 3: return "III";
        case 4: return "IV";
        case 5: return "V";
        default: return std::to_string( rank );
    }
}

std::string perk_display_name( const perk_def &perk )
{
    std::string result = russian() ? perk.name_ru : perk.name_en;
    const int rank = perk_rank( perk );
    if( perk_max_rank( perk ) > 1 && rank > 0 ) {
        result += " " + rank_roman( rank );
    }
    return result;
}

bool owned( const perk_def &perk )
{
    return perk_rank( perk ) > 0;
}
'@

$ownedStart = "bool owned( const perk_def &perk )"
$ownedEnd = "const perk_def *find_perk"
$sp = Replace-CppRange $sp $ownedStart $ownedEnd $rankHelpers "rank helpers"

$effectHelpers = @'
std::string ranked_effect_summary( const perk_def &perk, int rank )
{
    if( rank <= 0 ) {
        return {};
    }

    const double multiplier = perk_rank_multiplier_for( perk, rank );
    std::vector<std::string> parts;
    for( int i = 0; i < perk.effect_count; ++i ) {
        if( perk.effects[i].id == nullptr ) {
            continue;
        }
        const double value = perk.effects[i].value * multiplier;
        const std::string sign = value > 0.0 ? "+" : "";
        parts.push_back( effect_label( perk.effects[i].id ) + ": " +
                         sign + format_number( value ) );
    }
    if( perk.xp_bonus_pct != 0 ) {
        const int value = static_cast<int>(
                              std::llround( static_cast<double>( perk.xp_bonus_pct ) * multiplier ) );
        parts.push_back( tr( "Survivor XP: +", "Опыт Survivor: +" ) +
                         std::to_string( value ) + "%" );
    }

    std::string result;
    for( size_t i = 0; i < parts.size(); ++i ) {
        if( i != 0 ) {
            result += ", ";
        }
        result += parts[i];
    }
    return result;
}

std::string perk_description( const perk_def &perk )
{
    std::string result = russian() ? perk.desc_ru : perk.desc_en;
    const int max_rank = perk_max_rank( perk );
    if( max_rank <= 1 ) {
        return result;
    }

    const int rank = perk_rank( perk );
    result += "\n" + tr( "Rank ", "Ранг " ) + std::to_string( rank ) + "/" +
              std::to_string( max_rank );

    if( rank > 0 ) {
        result += "\n" + tr( "Current: ", "Сейчас: " ) +
                  ranked_effect_summary( perk, rank );
    }
    if( rank < max_rank ) {
        result += "\n" + tr( "Next: ", "Следующий: " ) +
                  ranked_effect_summary( perk, rank + 1 );
    }
    return result;
}

'@

$calcMarker = "struct calculated_effects {"
$calcPos = $sp.IndexOf($calcMarker)
if ($calcPos -lt 0) { throw "calculated_effects marker missing." }
$sp = $sp.Substring(0,$calcPos) + $effectHelpers + $sp.Substring($calcPos)

$newCalculate = @'
calculated_effects calculate_owned_effects()
{
    calculated_effects result;
    const std::array<branch_id, 6> branches = {
        branch_id::combat, branch_id::survival, branch_id::mobility,
        branch_id::crafting, branch_id::scavenging, branch_id::mastery
    };

    for( branch_id branch : branches ) {
        if( branch_owned_count( branch ) > 0 ) {
            ++result.active_branches;
        }
    }
    result.major_owned = owned_count( currency_id::major );

    for( const perk_def &perk : perks ) {
        if( !owned( perk ) || effective_kind( perk ) != perk_kind::effect ) {
            continue;
        }
        const double rank_scale = perk_rank_multiplier( perk );
        result.branch_amp[branch_index( perk.branch )] +=
            perk.branch_amp_pct * rank_scale / 100.0;
        result.global_amp += perk.global_amp_pct * rank_scale / 100.0;
    }

    for( const perk_def &perk : perks ) {
        if( !owned( perk ) ) {
            continue;
        }

        double scale = 1.0;
        if( perk.scaling == perk_scaling::per_active_branch ) {
            scale = static_cast<double>( result.active_branches );
        } else if( perk.scaling == perk_scaling::per_owned_major ) {
            scale = static_cast<double>( result.major_owned );
        }

        scale *= perk_rank_multiplier( perk );

        if( effective_kind( perk ) == perk_kind::stat ) {
            scale *= result.global_amp * result.branch_amp[branch_index( perk.branch )];
        }

        result.xp_bonus_pct += static_cast<int>( std::llround( perk.xp_bonus_pct * scale ) );
        for( int i = 0; i < perk.effect_count; ++i ) {
            if( perk.effects[i].id != nullptr ) {
                result.modifiers[perk.effects[i].id] += perk.effects[i].value * scale;
            }
        }
    }

    result.xp_bonus_pct = std::max( 0, std::min( 5000, result.xp_bonus_pct ) );
    return result;
}
'@

$sp = Replace-CppRange $sp "calculated_effects calculate_owned_effects()" `
    "std::map<std::string, double> owned_effect_totals()" $newCalculate "ranked effect calculation"

$newStatus = @'
std::string status_prefix( const perk_def &perk, int64_t level, int64_t perk_points, int64_t major_points )
{
    const int rank = perk_rank( perk );
    const int max_rank = perk_max_rank( perk );
    if( rank >= max_rank ) {
        return "[✓] ";
    }
    if( rank > 0 ) {
        return "[R" + std::to_string( rank ) + "/" + std::to_string( max_rank ) + "] ";
    }
    if( level < perk.required_level ) {
        return std::string( russian() ? "[УР " : "[L" ) +
               std::to_string( perk.required_level ) + "] ";
    }
    if( !prerequisites_met( perk ) ) {
        return russian() ? "[ТРЕБ.] " : "[REQ] ";
    }
    const bool enough = perk.currency == currency_id::perk ? perk_points > 0 : major_points > 0;
    if( !enough ) {
        return russian() ? "[НЕТ ОЧКОВ] " : "[NO POINTS] ";
    }
    return perk.currency == currency_id::perk ? "[1P] " : "[1M] ";
}
'@
$sp = Replace-CppRange $sp "std::string status_prefix(" "std::string cost_text(" $newStatus "ranked status prefix"

$newPurchase = @'
bool purchase_perk( const perk_def &perk )
{
    const int64_t level = branch_level( perk.branch );
    int64_t perk_points = get_state( "perk_points", 0 );
    int64_t major_points = get_state( "major_points", 0 );
    const int rank = perk_rank( perk );
    const int max_rank = perk_max_rank( perk );

    if( rank >= max_rank ) {
        message( tr( "This perk is already at maximum rank.",
                     "Этот перк уже максимального ранга." ) );
        return false;
    }
    if( level < perk.required_level ) {
        message( tr( "Your branch level is too low.", "Недостаточный уровень этой ветки." ) );
        return false;
    }
    if( !prerequisites_met( perk ) ) {
        message( tr( "Prerequisites are not met.", "Не выполнены требования предыдущих перков." ) );
        return false;
    }

    if( perk.currency == currency_id::perk ) {
        if( perk_points <= 0 ) {
            message( tr( "Not enough perk points.", "Недостаточно очков перков." ) );
            return false;
        }
        set_state( "perk_points", perk_points - 1 );
    } else {
        if( major_points <= 0 ) {
            message( tr( "Not enough major points.", "Недостаточно больших очков." ) );
            return false;
        }
        set_state( "major_points", major_points - 1 );
    }

    set_state( perk_key( perk ), rank + 1 );
    effects_dirty = true;
    recalculate_effects();

    std::string text = rank == 0 ?
                       tr( "Perk purchased: ", "Куплен перк: " ) :
                       tr( "Perk upgraded: ", "Перк улучшен: " );
    text += russian() ? perk.name_ru : perk.name_en;
    if( max_rank > 1 ) {
        text += " " + std::to_string( rank + 1 ) + "/" + std::to_string( max_rank );
    }
    message( text );
    return true;
}
'@
$sp = Replace-CppRange $sp "bool purchase_perk(" "void show_perk_detail(" $newPurchase "ranked purchase"

$newDetail = @'
void show_perk_detail( const perk_def &perk )
{
    while( true ) {
        const int level = static_cast<int>( branch_level( perk.branch ) );
        const int rank = perk_rank( perk );
        const int max_rank = perk_max_rank( perk );
        const bool maxed = rank >= max_rank;
        const bool unlocked = level >= perk.required_level && prerequisites_met( perk );

        std::string title = perk_display_name( perk );
        title += "\n" + perk_description( perk );
        title += "\n" + tr( "Tier ", "Тир " ) + std::to_string( perk.tier );
        title += " | " + tr( "Requires branch level ", "Нужен уровень ветки " ) +
                 std::to_string( perk.required_level );
        title += "\n" + tr( "Prerequisites: ", "Требования: " ) + prereq_text( perk );
        title += "\n" + tr( "Cost per rank: ", "Цена за ранг: " ) + cost_text( perk );

        std::string buy;
        if( maxed ) {
            buy = tr( "[Maximum rank]", "[Максимальный ранг]" );
        } else if( !unlocked ) {
            buy = tr( "Locked", "Закрыто" );
        } else if( rank > 0 ) {
            buy = tr( "Upgrade to rank ", "Улучшить до ранга " ) +
                  std::to_string( rank + 1 ) + "/" + std::to_string( max_rank );
        } else {
            buy = tr( "Purchase", "Купить" );
        }

        std::string back = tr( "Back", "Назад" );
        const char *entries[] = { buy.c_str(), back.c_str() };
        const int choice = host->ui_choose ? host->ui_choose( title.c_str(), entries, 2 ) : -1;
        if( choice != 0 ) {
            return;
        }
        if( maxed ) {
            return;
        }
        if( !unlocked ) {
            message( tr( "This perk is locked.", "Этот перк пока закрыт." ) );
            continue;
        }
        purchase_perk( perk );
        return;
    }
}
'@
$sp = Replace-CppRange $sp "void show_perk_detail(" "int branch_unlocked_count(" $newDetail "ranked perk detail"

$newUnlocked = @'
int branch_unlocked_count( branch_id branch, int64_t )
{
    const int64_t level = branch_level( branch );
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( perk.branch == branch && !perk_maxed( perk ) &&
            level >= perk.required_level && prerequisites_met( perk ) ) {
            ++result;
        }
    }
    return result;
}
'@
$sp = Replace-CppRange $sp "int branch_unlocked_count(" "struct card_text {" $newUnlocked "ranked unlocked count"

$newShowBranch = @'
void show_branch( branch_id branch )
{
    bool tree_mode = true;

    while( true ) {
        const int64_t level = branch_level( branch );
        const int64_t perk_points = get_state( "perk_points", 0 );
        const int64_t major_points = get_state( "major_points", 0 );

        std::vector<const perk_def *> branch_perks;
        branch_perks.reserve( 24 );
        std::vector<card_text> texts;
        texts.reserve( 24 );

        for( const perk_def &perk : perks ) {
            if( perk.branch != branch ) {
                continue;
            }
            branch_perks.push_back( &perk );

            const int rank = perk_rank( perk );
            const int max_rank = perk_max_rank( perk );
            const bool maxed = rank >= max_rank;
            const bool unlocked = level >= perk.required_level && prerequisites_met( perk );
            const bool enough = perk.currency == currency_id::perk ?
                                perk_points > 0 : major_points > 0;

            card_text card;
            card.id = perk.id;
            card.title = perk_display_name( perk );
            card.subtitle = "T" + std::to_string( perk.tier ) + " | " +
                            tr( "BLv ", "УрВ " ) + std::to_string( perk.required_level ) +
                            " | " + ( perk.currency == currency_id::perk ? "1P" : "1M" );
            if( max_rank > 1 ) {
                card.subtitle += " | " + tr( "R ", "Р " ) +
                                 std::to_string( rank ) + "/" + std::to_string( max_rank );
            }
            card.body = perk_description( perk );

            card.badge = perk_kind_label( perk ) + " | ";
            if( maxed ) {
                card.badge += max_rank > 1 ?
                              tr( "MAX ", "МАКС " ) + std::to_string( rank ) + "/" +
                              std::to_string( max_rank ) :
                              tr( "OWNED", "КУПЛЕНО" );
                card.flags |= NCMM_UI_CARD_OWNED;
            } else if( rank > 0 ) {
                card.badge += tr( "RANK ", "РАНГ " ) + std::to_string( rank ) + "/" +
                              std::to_string( max_rank );
                card.flags |= NCMM_UI_CARD_OWNED;
            } else if( !unlocked ) {
                card.badge += tr( "LOCKED", "ЗАКРЫТО" );
                card.flags |= NCMM_UI_CARD_LOCKED;
            } else if( !enough ) {
                card.badge += tr( "NO POINTS", "НЕТ ОЧКОВ" );
            } else {
                card.badge += tr( "AVAILABLE", "ДОСТУПНО" );
            }

            if( perk.currency == currency_id::major ) {
                card.flags |= NCMM_UI_CARD_MAJOR;
            }
            if( effective_kind( perk ) == perk_kind::effect ) {
                card.flags |= NCMM_UI_CARD_EFFECT;
            }
            card.icon_key = std::string( "survivor/perk/" ) + perk.id;
            texts.push_back( std::move( card ) );
        }

        const int owned_now = branch_owned_count( branch );
        const int total_now = branch_total_count( branch );
        const int unlocked_now = branch_unlocked_count( branch, level );

        std::string title = "Survivor Progression > " + branch_name( branch );
        std::string summary =
            tr( "Purchased ", "Куплено " ) + std::to_string( owned_now ) + "/" +
            std::to_string( total_now ) +
            tr( " | available ", " | доступно " ) + std::to_string( unlocked_now ) +
            " | P " + std::to_string( perk_points ) +
            " | M " + std::to_string( major_points );

        const int64_t blevel = branch_level( branch );
        const int64_t bxp = branch_xp( branch );
        const int64_t bnext = branch_xp_to_next( blevel );
        summary += tr( " | branch L", " | ветка ур." ) + std::to_string( blevel ) +
                   " XP " + std::to_string( bxp ) + "/" + std::to_string( bnext ) +
                   " | " + branch_efficiency_text( branch );

        std::string progress_label =
            branch_name( branch ) + tr( " XP -> L", " XP -> ур." ) +
            std::to_string( blevel + 1 );
        ncmm_ui_progress_v1 progress{
            progress_label.c_str(),
            bxp,
            bnext
        };

        if( tree_mode && host->ui_tree_choose ) {
            std::vector<tree_node_text> tree_texts;
            tree_texts.reserve( branch_perks.size() );
            std::map<std::string, size_t> index_by_id;

            for( size_t i = 0; i < branch_perks.size(); ++i ) {
                const perk_def &perk = *branch_perks[i];
                tree_node_text node;
                node.card = texts[i];
                node.card.body += "\n" + tr( "Prerequisites: ", "Требования: " ) +
                                  prereq_text( perk );
                const std::pair<int, int> position = branch_tree_position( branch, i );
                node.row = position.first;
                node.column = position.second;
                index_by_id[perk.id] = i;
                tree_texts.push_back( std::move( node ) );
            }

            std::vector<ncmm_ui_tree_edge_v1> edges;
            auto add_edge = [&]( const char *prereq, size_t to ) {
                if( prereq == nullptr || prereq[0] == '\0' ) {
                    return;
                }
                const auto it = index_by_id.find( prereq );
                if( it != index_by_id.end() ) {
                    edges.push_back( { it->second, to } );
                }
            };
            for( size_t i = 0; i < branch_perks.size(); ++i ) {
                add_edge( branch_perks[i]->prereq1, i );
                add_edge( branch_perks[i]->prereq2, i );
            }

            std::vector<ncmm_ui_tree_node_v1> nodes = bind_tree_nodes( tree_texts );
            const std::string tree_summary =
                summary + tr( " | Routed tree | Tab: cards",
                              " | Разведённое дерево | Tab: карточки" );
            const int choice = host->ui_tree_choose(
                                   title.c_str(), tree_summary.c_str(), &progress,
                                   nodes.data(), nodes.size(), edges.data(), edges.size() );
            if( choice == NCMM_UI_TREE_SHOW_CARDS ) {
                tree_mode = false;
                continue;
            }
            if( choice < 0 || static_cast<size_t>( choice ) >= branch_perks.size() ) {
                return;
            }
            show_perk_detail( *branch_perks[choice] );
            continue;
        }

        std::vector<ncmm_ui_card_v1> cards = bind_cards( texts );
        const std::string card_summary =
            summary + tr( " | Cards | Tab: tree",
                          " | Карточки | Tab: дерево" );
        const int choice = host->ui_card_choose ?
                           host->ui_card_choose( title.c_str(), card_summary.c_str(), &progress,
                                                 cards.data(), cards.size(), 2 ) :
                           -1;
        if( choice == NCMM_UI_CARD_SHOW_TREE ) {
            tree_mode = true;
            continue;
        }
        if( choice < 0 || static_cast<size_t>( choice ) >= branch_perks.size() ) {
            return;
        }
        show_perk_detail( *branch_perks[choice] );
    }
}
'@
$sp = Replace-CppRange $sp "void show_branch( branch_id branch )" "void show_overview()" $newShowBranch "0.9.10 branch UI"

$newRespec = @'
void respec()
{
    int64_t refund_perk = 0;
    int64_t refund_major = 0;
    for( const perk_def &perk : perks ) {
        const int rank = perk_rank( perk );
        if( rank <= 0 ) {
            continue;
        }
        if( perk.currency == currency_id::perk ) {
            refund_perk += rank;
        } else {
            refund_major += rank;
        }
    }

    if( refund_perk == 0 && refund_major == 0 ) {
        message( tr( "No Survivor perks to reset.", "Нет перков Survivor для сброса." ) );
        return;
    }

    std::string title = tr(
        "Respec all Survivor perks?\nRefund: ",
        "Сбросить все перки Survivor?\nВозврат: " );
    title += std::to_string( refund_perk ) + "P / " + std::to_string( refund_major ) + "M";
    title += tr( "\nRanked perks refund every purchased rank.",
                 "\nМногоуровневые перки возвращают очко за каждый купленный ранг." );

    std::string yes = tr( "Respec", "Сбросить" );
    std::string no = tr( "Cancel", "Отмена" );
    const char *entries[] = { yes.c_str(), no.c_str() };
    const int choice = host->ui_choose ? host->ui_choose( title.c_str(), entries, 2 ) : -1;
    if( choice != 0 ) {
        return;
    }

    for( const perk_def &perk : perks ) {
        if( perk_rank( perk ) > 0 ) {
            set_state( perk_key( perk ), 0 );
        }
    }

    set_state( "perk_points", get_state( "perk_points", 0 ) + refund_perk );
    set_state( "major_points", get_state( "major_points", 0 ) + refund_major );
    set_state( "fast_learner", 0 );
    effects_dirty = true;
    recalculate_effects();

    message( tr( "Survivor perks reset. Refunded: ", "Перки Survivor сброшены. Возвращено: " ) +
             std::to_string( refund_perk ) + "P / " + std::to_string( refund_major ) + "M" );
}
'@
$sp = Replace-CppRange $sp "void respec()" "void open_progression()" $newRespec "ranked respec"

# Keep the log/descriptor version synchronized even if snapshot had extra text.
$sp = $sp.Replace(
    "anti-farm branch XP / 120 perks / 6 integrated RPG trees.",
    "anti-farm branch XP / routed trees / ranked foundational perks."
)

Write-Utf8NoBom $spPath $sp

$manifestPath = Join-Path $Source0910 "mod.json"
$manifest = [IO.File]::ReadAllText($manifestPath)
$manifest = $manifest.Replace('"version": "0.9.9"','"version": "0.9.10"')
Write-Utf8NoBom $manifestPath $manifest

