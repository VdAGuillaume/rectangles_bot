# bot.jl 


# STRUCTURE D'ÉTAT DU BOT

# BotState contient tout ce dont le bot a besoin pour résoudre :
#   coverage : matrice H×W — 0 = libre, sinon le numéro du rectangle qui couvre la case
#   placed   : liste des rectangles déjà placés (dans l'ordre)
#   W, H     : dimensions de la grille
mutable struct BotState
    coverage :: Matrix{Int64}
    placed   :: Vector{Rectangle}
    W        :: Int64
    H        :: Int64
end

# Crée un BotState vierge pour une grille W×H.
function make_bot(W::Int64, H::Int64)::BotState
    coverage = fill(0, H, W)   # matrice H×W remplie de zéros 
    placed   = Rectangle[]     # tableau vide 
    return BotState(coverage, placed, W, H)
end


# UTILITAIRES DE BASE

# Vérifie qu'un rectangle est valide selon les règles du jeu :
# il doit contenir EXACTEMENT un indice (chiffre) égal à son aire (w × h).
function rect_valid(rec::Rectangle, grid::Matrix{Int64})::Bool
    area::Int64  = rec.w * rec.h
    count::Int64 = 0

    for j in rec.y : rec.y + rec.h - 1        # parcourt les lignes  
        for i in rec.x : rec.x + rec.w - 1    # parcourt les colonnes
            v::Int64 = grid[j, i]
            if v != 0                          # case non vide = indice trouvé
                count = count + 1
                if v != area || count > 1      # mauvaise valeur OU trop d'indices
                    return false
                end
            end
        end
    end
    return count == 1   # valide seulement si exactement 1 indice
end

# Vérifie que toutes les cases d'un rectangle sont libres dans coverage.
function rect_placeable(bot::BotState, rec::Rectangle)::Bool
    for j in rec.y : rec.y + rec.h - 1
        for i in rec.x : rec.x + rec.w - 1
            if bot.coverage[j, i] != 0    # case déjà occupée par un autre rectangle
                return false
            end
        end
    end
    return true
end

# Marque les cases du rectangle comme occupées et l'ajoute à placed.
function place_rect!(bot::BotState, rec::Rectangle)
    idx::Int64 = length(bot.placed) + 1   # numéro unique du rectangle 
    for j in rec.y : rec.y + rec.h - 1
        for i in rec.x : rec.x + rec.w - 1
            bot.coverage[j, i] = idx
        end
    end
    push!(bot.placed, rec)                 # ajoute en fin de tableau 
end

# Extrait tous les indices visibles de la grille :
# retourne un dictionnaire (colonne, ligne) → valeur de l'indice.
function find_clues(grid::Matrix{Int64})::Dict{Tuple{Int64,Int64}, Int64}
    clues = Dict{Tuple{Int64,Int64}, Int64}()
    H::Int64, W::Int64 = size(grid)        

    for j in 1:H
        for i in 1:W
            if grid[j, i] > 0
                clues[(i, j)] = grid[j, i]
            end
        end
    end
    return clues
end

# Génère tous les rectangles valides et plaçables pour l'indice (cx, cy) d'aire donnée.
# Un candidat doit : contenir (cx, cy), avoir exactement l'aire demandée,
# ne couvrir qu'un seul indice, et avoir toutes ses cases libres.
function candidate_rects(bot::BotState, cx::Int64, cy::Int64, area::Int64,
                         grid::Matrix{Int64})::Vector{Rectangle}
    candidates = Rectangle[]

    for w in 1:area                        # teste toutes les largeurs possibles
        if area % w != 0                  
            continue
        end
        h::Int64 = area ÷ w               # hauteur correspondante 

        # Le coin supérieur-gauche (x, y) doit être tel que (cx, cy) soit à l'intérieur
        x_min::Int64 = max(1, cx - w + 1)
        x_max::Int64 = min(bot.W - w + 1, cx)
        y_min::Int64 = max(1, cy - h + 1)
        y_max::Int64 = min(bot.H - h + 1, cy)

        for x in x_min:x_max
            for y in y_min:y_max
                rec = Rectangle(x, y, w, h)
                if rect_valid(rec, grid) && rect_placeable(bot, rec)
                    push!(candidates, rec)  
                end
            end
        end
    end
    return candidates
end

# Vérifie que la grille est entièrement couverte et que chaque rectangle est valide.
function puzzle_solved(bot::BotState, grid::Matrix{Int64})::Bool
    total_area::Int64 = 0
    for rec in bot.placed
        if !rect_valid(rec, grid)
            return false
        end
        total_area = total_area + rec.w * rec.h
    end
    return total_area == bot.W * bot.H
end


# PHASE 1 — PROPAGATION DE CONTRAINTES 


# On commence toujours par chercher les cases "évidentes" :
# un indice qui n'a qu'une seule façon d'être entouré d'un rectangle.
# On répète jusqu'à ce qu'il n'y ait plus de cas évidents.
#
# Retourne true si au moins un rectangle a été placé.

function propagate!(bot::BotState, grid::Matrix{Int64})::Bool
    clues      = find_clues(grid)
    any_placed = false   # a-t-on placé quelque chose au cours de cet appel ?
    progress   = true    # reste-t-il des cas évidents à traiter ?

    while progress                            
        progress = false

        for ((cx, cy), area) in clues        
            if bot.coverage[cy, cx] != 0       # cet indice est déjà couvert → passer
                continue
            end

            cands = candidate_rects(bot, cx, cy, area, grid)

            if length(cands) == 0              # aucun placement possible = impasse
                return any_placed

            elseif length(cands) == 1          # UN SEUL choix → placement forcé 
                place_rect!(bot, cands[1])
                progress   = true              # on a progressé, on repart d'un nouveau tour
                any_placed = true
            end
            # Si plusieurs candidats : on laisse pour la phase suivante
        end
    end

    return any_placed
end



# PHASE 2 — CHOIX DE L'INDICE LE PLUS CONTRAINT

# Quand il n'y a plus de cas évidents, on choisit
# l'indice qui a le MOINS de possibilités restantes :
# c'est le plus "facile" à deviner (moins de risque de se tromper).
# Retourne (cx, cy, area) ou (-1, -1, -1) si tout est couvert (valeur sentinelle)

function most_constrained_clue(bot::BotState, grid::Matrix{Int64})::Tuple{Int64,Int64,Int64}
    clues      = find_clues(grid)
    best       = (-1, -1, -1)          # résultat par défaut 
    best_count = bot.W * bot.H + 1     # très grand nombre de départ

    for ((cx, cy), area) in clues
        if bot.coverage[cy, cx] != 0   # déjà couvert → ignorer
            continue
        end
        cands = candidate_rects(bot, cx, cy, area, grid)
        if length(cands) < best_count  # cet indice est plus contraint que le précédent
            best_count = length(cands)
            best       = (cx, cy, area)
        end
    end

    return best
end



# PHASE 3 — BOUCLE PRINCIPALE DE RÉSOLUTION (style humain)
#
# On alterne entre :
#   - propagation (trouver les cases évidentes et les remplir)
#   - essai sur le cas le plus contraint quand il est bloqué
#   - effacement et nouvel essai si le choix mène à une impasse
#
# On utilise une pile (Vector) de sauvegardes d'état pour pouvoir
# "effacer" un mauvais choix et revenir en arrière.

function solve(state::GameState)::Union{Vector{Rectangle}, Nothing}
    bot::BotState = make_bot(state.w, state.h)

    # Chaque entrée de la pile est un tuple :
   
    pile = Vector{Tuple{Matrix{Int64}, Vector{Rectangle}, Vector{Rectangle}}}()

    # Boucle principale 
    while true

        # Étape 1 : propager les contraintes (placer tous les cas évidents)
        propagate!(bot, state.grid)

        # Étape 2 : le puzzle est-il résolu ?
        if puzzle_solved(bot, state.grid)
            return bot.placed
        end

        # Étape 3 : chercher l'indice le plus contraint
        clue = most_constrained_clue(bot, state.grid)

        if clue != (-1, -1, -1)
            # On a trouvé un indice non encore couvert
            (cx, cy, area) = clue
            cands = candidate_rects(bot, cx, cy, area, state.grid)

            if length(cands) > 0
                # Sauvegarder l'état AVANT de faire un choix risqué
                # On garde tous les candidats sauf le premier qu'on va essayer maintenant
                coverage_save = copy(bot.coverage)  # copie de la matrice 
                placed_save   = copy(bot.placed)    # copie du tableau    
                rest          = cands[2:end]        # les autres candidats à essayer plus tard

                push!(pile, (coverage_save, placed_save, rest))  # empiler 

                # Essayer le premier candidat
                place_rect!(bot, cands[1])
                continue   # recommencer la boucle avec ce nouveau placement
            end
        end

        # Étape 4 : on est bloqué (impasse ou plus d'indice non couvert avec candidats)
        # → Revenir en arrière, on efface et essaie autre chose

        backtracked = false

        while length(pile) > 0          # tant qu'il reste des sauvegardes
            (coverage_save, placed_save, rest) = pop!(pile)   # dépiler 

            if length(rest) > 0         # reste-t-il des candidats à essayer ?
                # Restaurer l'état sauvegardé
                bot.coverage = copy(coverage_save)
                bot.placed   = copy(placed_save)

                # Sauvegarder à nouveau avec les candidats restants moins un
                rest2 = rest[2:end]
                push!(pile, (coverage_save, placed_save, rest2))

                # Essayer le prochain candidat
                place_rect!(bot, rest[1])
                backtracked = true
                break
            end
            # Sinon : plus de candidats pour ce niveau → remonter encore d'un niveau
        end

        if !backtracked
            return nothing   # plus aucune solution possible
        end
    end
end
