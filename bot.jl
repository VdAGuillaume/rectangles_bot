# bot.jl  —  Solveur du jeu Rectangles



# BotState représente l'état interne du solveur.
# On peut modifier ses champs au fil de la résolution.
#   - coverage : matrice H×W indiquant quelle cellule est déjà
#                couverte par un rectangle (0 = libre, sinon
#                l'indice du rectangle qui la couvre)
#   - placed   : liste des rectangles déjà placés
#   - W, H     : dimensions de la grille


mutable struct BotState
    coverage :: Matrix{Int64}
    placed   :: Vector{Rectangle}
    W        :: Int64
    H        :: Int64
end

# Crée un BotState vierge pour une grille de taille W×H.
function make_bot(W::Int64, H::Int64)::BotState
    coverage = fill(0, H, W)  # matrice H×W remplie de 0
    placed   = Rectangle[]    # tableau vide de rectangles
    return BotState(coverage, placed, W, H)
end



# UTILITAIRES

# Teste si deux rectangles (en coordonnées de tuile) se chevauchent.
# On sépare les tests horizontal et vertical pour la clarté.
# Deux rectangles ne se chevauchent PAS si l'un est entièrement
# à gauche, à droite, au-dessus ou en-dessous de l'autre.
function rects_overlap(a::Rectangle, b::Rectangle)::Bool
    horizontal = a.x + a.w <= b.x || b.x + b.w <= a.x  # l'un est à gauche de l'autre
    vertical   = a.y + a.h <= b.y || b.y + b.h <= a.y  # l'un est au-dessus de l'autre
    return !(horizontal || vertical)                     # chevauchement = ni l'un ni l'autre
end

# Vérifie qu'un rectangle est valide selon les règles du jeu :
# il doit contenir EXACTEMENT un indice égal à son aire.
function rect_valid(rec::Rectangle, grid::Matrix{Int64})::Bool
    count::Int64 = 0           # nombre d'indices trouvés dans le rectangle
    area::Int64  = rec.w * rec.h  # aire du rectangle

    for i in rec.x : rec.x + rec.w - 1  # colonnes
        for j in rec.y : rec.y + rec.h - 1  # lignes
            v::Int64 = grid[j, i]        # valeur de la cellule
            if v != 0                    # cellule non vide = indice trouvé
                count = count + 1
                if v != area || count > 1  # mauvaise valeur ou trop d'indices
                    return false
                end
            end
        end
    end
    return count == 1  # valide seulement si exactement 1 indice trouvé
end

# Vérifie si la liste de rectangles placés couvre exactement
# toute la grille et que chaque rectangle est valide.
function puzzle_solved(placed::Vector{Rectangle}, grid::Matrix{Int64}, W::Int64, H::Int64)::Bool
    total_area::Int64 = 0
    for rec in placed
        if !rect_valid(rec, grid)
            return false
        end
        total_area = total_area + rec.w * rec.h  # accumulation des aires
    end
    return total_area == W * H  # la somme des aires doit couvrir toute la grille
end

# Extrait tous les indices visibles de la grille sous forme de
# dictionnaire : (colonne, ligne) → valeur de l'indice.
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

# Retourne true si la cellule (x, y) n'est pas encore couverte.
function cell_free(bot::BotState, x::Int64, y::Int64)::Bool
    return bot.coverage[y, x] == 0
end

# Vérifie que toutes les cellules d'un rectangle sont libres
# dans la couverture actuelle.
function rect_placeable(bot::BotState, rec::Rectangle)::Bool
    for j in rec.y : rec.y + rec.h - 1
        for i in rec.x : rec.x + rec.w - 1
            if bot.coverage[j, i] != 0   # cellule déjà occupée
                return false
            end
        end
    end
    return true  # toutes les cellules sont libres
end

# Marque toutes les cellules du rectangle comme occupées (valeur idx)
# et ajoute le rectangle à la liste des rectangles placés.
function place_rect!(bot::BotState, rec::Rectangle, idx::Int64)
    for j in rec.y : rec.y + rec.h - 1
        for i in rec.x : rec.x + rec.w - 1
            bot.coverage[j, i] = idx
        end
    end
    push!(bot.placed, rec)
end

# Retire un rectangle : remet ses cellules à 0 dans coverage
# et le supprime de la liste placed.
function remove_rect!(bot::BotState, rec::Rectangle, idx::Int64)
    new_placed = Rectangle[]
    for r in bot.placed
        if r != rec
            push!(new_placed, r)
        end
    end
    bot.placed = new_placed

    for j in rec.y : rec.y + rec.h - 1
        for i in rec.x : rec.x + rec.w - 1
            bot.coverage[j, i] = 0
        end
    end
end

# Génère tous les rectangles valides et plaçables pour l'indice
# situé en (cx, cy) avec une aire donnée.
# Un candidat doit : contenir (cx, cy), avoir l'aire exacte,
# ne couvrir qu'un seul indice, et avoir toutes ses cellules libres.
function candidate_rects(bot::BotState, cx::Int64, cy::Int64, area::Int64, grid::Matrix{Int64})::Vector{Rectangle}
    candidates = Rectangle[]

    for w in 1:area
        if area % w != 0
            continue
        end
        h::Int64     = area ÷ w      # hauteur correspondante

        # bornes du coin supérieur-gauche pour que (cx,cy) soit dans le rectangle
        x_min::Int64 = max(1, cx - w + 1)
        x_max::Int64 = min(bot.W - w + 1, cx)
        y_min::Int64 = max(1, cy - h + 1)
        y_max::Int64 = min(bot.H - h + 1, cy)

        for x in x_min:x_max
            for y in y_min:y_max
                rec = Rectangle(x, y, w, h)
                if !rect_valid(rec, grid)
                    continue
                end
                if rect_placeable(bot, rec)
                    push!(candidates, rec)
                end
            end
        end
    end
    return candidates
end



# PHASE 1 — PROPAGATION DE CONTRAINTES
# Si un indice n'a qu'un seul rectangle possible, ce placement
# est forcé. On répète jusqu'à ce qu'il n'y ait plus aucun
# placement évident (comme la résolution d'un Sudoku).


function propagate!(bot::BotState, grid::Matrix{Int64})::Bool
    clues      = find_clues(grid)
    progress   = true   # vrai tant qu'on a placé au moins un rectangle
    any_placed = false  # indique si la fonction a placé quelque chose

    while progress
        progress = false

        for ((cx, cy), area) in clues
            if bot.coverage[cy, cx] != 0  # cet indice est déjà couvert
                continue
            end

            cands = candidate_rects(bot, cx, cy, area, grid)

            if length(cands) == 0      # aucun candidat = contradiction
                return any_placed
            elseif length(cands) == 1  # un seul candidat = placement forcé
                rec        = cands[1]
                idx::Int64 = length(bot.placed) + 1
                place_rect!(bot, rec, idx)
                progress   = true   # on a progressé, on recommence un tour
                any_placed = true
            end
            # si plusieurs candidats : on laisse pour le backtracking
        end
    end

    return any_placed
end



# PHASE 2a — SÉLECTION DU MEILLEUR INDICE
# Parmi les indices non encore couverts, on choisit celui qui a
# le moins de rectangles candidats possibles (heuristique MRV).
# Cela réduit l'arbre de recherche du backtracking.


function first_uncovered_clue(bot::BotState, grid::Matrix{Int64})::Tuple{Int64,Int64,Int64}
    clues      = find_clues(grid)
    best       = (-1, -1, -1)
    best_count = bot.W * bot.H + 1   # valeur initiale très grande

    for ((cx, cy), area) in clues
        if bot.coverage[cy, cx] != 0  # déjà couvert, on ignore
            continue
        end
        cands = candidate_rects(bot, cx, cy, area, grid)
        if length(cands) < best_count
            best_count = length(cands)
            best       = (cx, cy, area)
        end
    end

    return best
end


# PHASE 2b — BACKTRACKING RÉCURSIF
# Algorithme :
#   1. Propager les contraintes (placements forcés)
#   2. Si tout est résolu → succès
#   3. Choisir l'indice avec le moins de candidats
#   4. Essayer chaque candidat :
#      - sauvegarder l'état
#      - placer le rectangle
#      - appel récursif
#      - si échec → restaurer l'état et essayer le suivant


function backtrack!(bot::BotState, grid::Matrix{Int64})::Bool
    propagate!(bot, grid)  # Phase 1 : placements forcés d'abord

    # si la grille est entièrement couverte et valide → succès
    if puzzle_solved(bot.placed, grid, bot.W, bot.H)
        return true
    end

    # on cherche l'indice le plus contraint à traiter
    clue::Tuple{Int64,Int64,Int64} = first_uncovered_clue(bot, grid)

    if clue == (-1, -1, -1)
        return false          # contradiction
    end

    (cx, cy, area) = clue
    cands          = candidate_rects(bot, cx, cy, area, grid)

    if length(cands) == 0    # plus aucun candidat = impasse
        return false
    end

    for rec in cands
        idx::Int64 = length(bot.placed) + 1

        coverage_backup = copy(bot.coverage)
        placed_backup   = copy(bot.placed)

        place_rect!(bot, rec, idx)  # on tente ce rectangle

        if backtrack!(bot, grid)
            return true             # solution trouvée !
        end

        bot.coverage = coverage_backup
        bot.placed   = placed_backup
    end

    return false  # aucun candidat n'a mené à une solution
end



# POINT D'ENTRÉE
# solve() est appelé depuis main.jl avec le GameState courant.
# Elle crée un BotState vierge, lance le backtracking et retourne
# la liste des rectangles solution, ou nothing si pas de solution.


function solve(state::GameState)::Union{Vector{Rectangle}, Nothing}
    bot::BotState = make_bot(state.w, state.h)

    if backtrack!(bot, state.grid)
        return bot.placed           # solution trouvée
    else
        return nothing              # pas de solution
    end
end

