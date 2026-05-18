module Grid;
export Rectangle, GameState, generate_puzzle;

using Random
using Random: shuffle!

###############################
# Structures
###############################

mutable struct Rectangle
    x::Int64
    y::Int64
    w::Int64
    h::Int64
end

mutable struct GameState
    w::Int64
    h::Int64
    grid::Matrix{Int64}
    win_rects::Vector{Rectangle}
    rects::Vector{Rectangle}
    focus::Vector{Int64}
    hover::Vector{Int64}
    won::Bool
    custom_str::String
end

###############################
# CONSTANTES GLOBALES
###############################

# distance entre une coupe et le bord d'un rectangle
const BASE_MARGIN = 3
# aire minimale acceptée -> les petits sont créés indirectement
const MIN_AREA_BEFORE_CUT = 12

# décalage d'une coupe pile au milieu
const CUT_OFFSETS = [-3,-2,-1,0,1,2,3]

# classes d'aire
const AREA_CLASSES = [
    (2, 5, 0.50),
    (6, 10, 0.35),
    (11, 15, 0.08),
    (16, 25, 0.05),
    (26, 40, 0.02)
]

const NORM_CLASSES = let
    total_p = sum(c[3] for c in AREA_CLASSES)
    [(a,b,p/total_p) for (a,b,p) in AREA_CLASSES]
end

###############################
# Outils grille
###############################

"""
    rect_is_free(state, r) -> Bool

Vérifie si toutes les tuiles couvertes par `r` sont libres (valeur 0) dans `state.grid`.

Parcourt chaque case (x, y) du rectangle et retourne `false` dès qu'une case est occupée.
Retourne `true` si le rectangle peut être placé sans conflit.

# Arguments
- `state::GameState` : état courant (la grille solution y est stockée)
- `r::Rectangle`     : rectangle à tester

# Retourne
`true` si la zone est entièrement libre, `false` sinon.
"""
@inline function rect_is_free(state::GameState, r::Rectangle)
	@inbounds for y in r.y:r.y+r.h-1
		for x in r.x:r.x+r.w-1
			if state.grid[y,x] != 0
				return false
			end
		end
	end
	return true
end

"""
    place!(state, r, S)

Écrit la valeur `S` dans toutes les tuiles couvertes par `r` dans `state.grid`.

Utilisé pour marquer une zone comme occupée par un rectangle d'identifiant (ou d'aire) `S`.

# Arguments
- `state::GameState` : état courant (modifié en place)
- `r::Rectangle`     : rectangle à remplir
- `S::Int64`         : valeur à écrire (aire du rectangle)
"""
@inline function place!(state::GameState, r::Rectangle, S::Int64)
	@inbounds for y in r.y:r.y+r.h-1, x in r.x:r.x+r.w-1
		state.grid[y,x] = S
	end
end

"""
    remove!(state, r)

Remet à 0 toutes les tuiles couvertes par `r` dans `state.grid`.

Opération inverse de `place!`, utilisée pour annuler un placement ou réinitialiser une zone.

# Arguments
- `state::GameState` : état courant (modifié en place)
- `r::Rectangle`     : rectangle à effacer
"""
@inline function remove!(state::GameState, r::Rectangle)
	@inbounds for y in r.y:r.y+r.h-1, x in r.x:r.x+r.w-1
		state.grid[y,x] = 0
	end
end

"""
    safe_margin(n) -> Int

Calcule une marge sûre adaptée à la dimension `n` d'un rectangle.

La marge est plafonnée à `BASE_MARGIN` et ne descend pas en dessous de 1.
Pour les petites dimensions, utilise `n÷3` pour éviter des coupes trop proches des bords.

# Arguments
- `n` : largeur ou hauteur du rectangle

# Retourne
Un entier compris entre 1 et `BASE_MARGIN`.
"""
@inline function safe_margin(n)
    return min(BASE_MARGIN, max(1, div(n,3)))
end

###############################
# COUPE VERTICALE
###############################

"""
    try_vertical_cut(r) -> Union{Tuple{Rectangle,Rectangle}, Nothing}

Tente de couper le rectangle `r` verticalement (en deux sous-rectangles gauche/droite).

Retourne `nothing` si la largeur est trop faible (≤ 2) ou si la coupe produirait
un rectangle invalide (1×1). Sinon, calcule une position de coupe aléatoire avec
une marge de sécurité et un offset aléatoire, puis retourne le couple `(gauche, droite)`.

# Arguments
- `r::Rectangle` : rectangle à couper

# Retourne
Un tuple `(left, right)` de deux rectangles, ou `nothing` si la coupe est impossible.
"""
function try_vertical_cut(r::Rectangle)
    if r.w <= 2
        return nothing
    end

    m = safe_margin(r.w)

    if r.w > 2*m
        base_cut = rand(m:r.w-m)
    else
        base_cut = rand(1:r.w-1)
    end

    offset = rand(CUT_OFFSETS)
    cut_local = clamp(base_cut + offset, 1, r.w-1)
    cut = r.x + cut_local

    wL = cut - r.x
    wR = r.x + r.w - cut

    # blindages
    if wL <= 0 || wR <= 0
        return nothing
    end
    if (wL == 1 && r.h == 1) || (wR == 1 && r.h == 1)
        return nothing
    end

    left  = Rectangle(r.x, r.y, wL, r.h)
    right = Rectangle(cut, r.y, wR, r.h)

    return (left, right)
end

###############################
# COUPE HORIZONTALE
###############################

"""
    try_horizontal_cut(r) -> Union{Tuple{Rectangle,Rectangle}, Nothing}

Tente de couper le rectangle `r` horizontalement (en deux sous-rectangles haut/bas).

Retourne `nothing` si la hauteur est trop faible (≤ 2) ou si la coupe produirait
un rectangle invalide (1×1). Sinon, calcule une position de coupe aléatoire avec
une marge de sécurité et un offset aléatoire, puis retourne le couple `(haut, bas)`.

# Arguments
- `r::Rectangle` : rectangle à couper

# Retourne
Un tuple `(top, bottom)` de deux rectangles, ou `nothing` si la coupe est impossible.
"""
function try_horizontal_cut(r::Rectangle)
    if r.h <= 2
        return nothing
    end

    m = safe_margin(r.h)
    if r.h > 2*m
        base_cut = rand(m:r.h-m)
    else
        base_cut = rand(1:r.h-1)
    end


    offset = rand(CUT_OFFSETS)
    cut_local = clamp(base_cut + offset, 1, r.h-1)
    cut = r.y + cut_local

    hT = cut - r.y
    hB = r.y + r.h - cut

    # blindages
    if hT <= 0 || hB <= 0
        return nothing
    end
    if (hT == 1 && r.w == 1) || (hB == 1 && r.w == 1)
        return nothing
    end

    top    = Rectangle(r.x, r.y, r.w, hT)
    bottom = Rectangle(r.x, cut, r.w, hB)

    return (top, bottom)
end

###############################
# Générateur structuré
###############################

"""
    pick_target_area() -> Int

Tire aléatoirement une aire cible selon la distribution de probabilités définie dans `norm_classes`.

Parcourt les classes d'aire normalisées en accumulant les probabilités et retourne
une aire entière aléatoire dans la classe sélectionnée.
Retourne une aire entre 2 et 5 par défaut si aucune classe n'est tirée.

# Retourne
Un entier représentant l'aire cible souhaitée pour un rectangle.
"""
function pick_target_area()
    r = rand()
    acc = 0.0
    for (amin,amax,p) in NORM_CLASSES
        acc += p
        if r <= acc
            return rand(amin:amax)
        end
    end
    return rand(2:5)
end 


"""
    dynamic_tol(area, W, H) -> Float64

Calcule une tolérance dynamique pour comparer l'aire d'un rectangle à son aire cible.

La tolérance augmente avec l'aire totale de la grille (W×H) et avec l'aire du rectangle,
afin de permettre plus de souplesse sur les grandes grilles et les grands rectangles.

# Arguments
- `area` : aire actuelle du rectangle évalué
- `W`    : largeur de la grille
- `H`    : hauteur de la grille

# Retourne
Un `Float64` représentant la tolérance relative maximale acceptée.
"""
function dynamic_tol(area, W, H)
    A = W * H

    # Matrice des seuils :
    # Chaque entrée = (A_max, tol_area≤10, tol_area≤25, tol_area>25)
    table = [
        (100, 0.15, 0.30, 0.45)
        (200, 0.25, 0.55, 0.85)
        (300, 0.30, 0.78, 1.25)
        (Inf, 0.35, 0.95, 1.70)
    ]

    # On parcourt la table pour trouver la bonne ligne
    for (Amax, t10, t25, tbig) in table
        if A <= Amax
            if area <= 10
                return t10
            elseif area <= 25
                return t25
            else
                return tbig
            end
        end
    end
end


"""
    generate_rectangles_structured(W, H) -> Vector{Rectangle}

Génère une partition aléatoire de la grille W×H en rectangles via un algorithme de découpe récursive (BSP).

Part d'un rectangle couvrant toute la grille et le découpe itérativement (verticalement
ou horizontalement) en alternant les sens de coupe pour éviter les répétitions.
Chaque rectangle est accepté tel quel si son aire est proche de l'aire cible
(selon la tolérance dynamique), trop petite pour être coupée, ou si la coupe échoue.

# Arguments
- `W::Int` : largeur de la grille
- `H::Int` : hauteur de la grille

# Retourne
Un `Vector{Rectangle}` partitionnant exactement la grille W×H.
"""
function generate_rectangles_structured(W, H)
    rects = Rectangle[]
    queue = [(Rectangle(1,1,W,H), :none)]

    # normalisation des probabilités
    total_p = sum(c[3] for c in AREA_CLASSES)
    norm_classes = [(a,b,p/total_p) for (a,b,p) in AREA_CLASSES]

    while !isempty(queue)
        (r, last_cut) = pop!(queue)

        # 1×1 → accepter
        if r.w == 1 && r.h == 1
            push!(rects, r)
            continue
        end

        area   = r.w * r.h
        target = pick_target_area()
        tol    = dynamic_tol(area, W, H)

        # trop petit pour couper
        if area < MIN_AREA_BEFORE_CUT && area > target
            push!(rects, r)
            continue
        end

        # assez proche de la cible
        if abs(area - target) <= target * tol
            push!(rects, r)
            continue
        end

        # ============================
        # CHOIX DU SENS DE COUPE
        # ============================
        if last_cut == :horizontal
            do_vertical = true
        elseif last_cut == :vertical
            do_vertical = false
        else
            do_vertical = rand() < 0.5
        end

        # ============================
        # APPLICATION DE LA COUPE
        # ============================
        if do_vertical
            cut = try_vertical_cut(r)

            if cut === nothing
                push!(rects, r)
            else
                (left, right) = cut
                push!(queue, (left, :vertical))
                push!(queue, (right, :vertical))
            end

        else
            cut = try_horizontal_cut(r)

            if cut === nothing
                push!(rects, r)
            else
                (top, bottom) = cut
                push!(queue, (top, :horizontal))
                push!(queue, (bottom, :horizontal))
            end
        end
    end

    return rects
end

###############################
# Indices centrés
###############################

"""
    generate_area_centers(state) -> Vector{Tuple{Int64,Int64}}

Calcule la position centrale (en tuiles) de chaque rectangle solution.

C'est à ces positions que sera affiché l'indice numérique (l'aire) dans la grille joueur.
Le centre est calculé par division entière, donc il est toujours à l'intérieur du rectangle.

# Arguments
- `state::GameState` : état courant (les rectangles solution sont dans `state.win_rects`)

# Retourne
Un vecteur de tuples `(cx, cy)` de longueur `length(state.win_rects)`,
où `cx` est la colonne et `cy` la ligne du centre du i-ème rectangle.
"""
function generate_area_centers(state::GameState)
    N    = length(state.win_rects)
    area = Vector{Tuple{Int64,Int64}}(undef, N)
    for i in 1:N
        r       = state.win_rects[i]
        area[i] = (r.x + div(r.w, 2), r.y + div(r.h, 2))
    end
    return area
end

###############################
# Génération du puzzle
###############################

"""
    generate_puzzle(W, H) -> GameState

Point d'entrée principal de la génération : crée un puzzle complet de taille W×H.

## Étapes
1. Génère une partition aléatoire de la grille via `generate_rectangles_structured`.
2. Initialise un `GameState` vierge avec ces rectangles comme solution.
3. Place chaque rectangle dans la grille avec son aire comme valeur.
4. Calcule les centres de chaque rectangle solution (`generate_area_centers`).
5. Construit la grille joueur via `make_player_grid` : seules les cases centrales
   contiennent l'indice (aire), toutes les autres restent à 0.

# Arguments
- `W::Int` : largeur souhaitée de la grille
- `H::Int` : hauteur souhaitée de la grille

# Retourne
Un `GameState` prêt à être joué, avec `grid` représentant la vue joueur.
"""
function generate_puzzle(W, H)
    win_rects = generate_rectangles_structured(W, H)
    state     = GameState(W, H, fill(0, H, W), win_rects, Rectangle[], [-1, -1], [-1, -1], false, "")

    for r in win_rects
        place!(state, r, r.w * r.h)
    end

    state.grid = make_player_grid(state, generate_area_centers(state))
    return state
end

###############################
# Grille joueur
###############################

"""
    make_player_grid(state, area) -> Matrix{Int64}

Construit la grille visible par le joueur à partir des centres des rectangles gagnants.

Crée une matrice vide de la taille de la grille, puis pour chaque rectangle,
place la valeur de son aire (w×h) uniquement à la cellule centrale (cx, cy).
Le reste de la grille reste à 0, constituant l'état initial du puzzle pour le joueur.

# Arguments
- `state::GameState`                 : état courant (contient `win_rects`)
- `area::Vector{Tuple{Int64,Int64}}` : centres calculés par `generate_area_centers`

# Retourne
Une `Matrix{Int64}` de taille H×W, vierge sauf aux positions centrales des rectangles.
"""
function make_player_grid(state::GameState, area)
    H, W   = size(state.grid)
    player = fill(0, H, W)
    for (i, (cx, cy)) in enumerate(area)
        r              = state.win_rects[i]
        player[cy, cx] = r.w * r.h
    end
    return player
end

###############################
# Affichage
###############################

"""
    print_grid(mat)

Affiche une matrice entière dans le terminal, ligne par ligne, valeurs séparées par des espaces.

Utile pour déboguer la génération sans interface graphique.

# Arguments
- `mat::Matrix{Int}` : matrice à afficher (typiquement `state.grid`)
"""
function print_grid(mat::Matrix{Int})
    H, W = size(mat)
    for y in 1:H
        println(join(mat[y,:], " "))
    end
end

###############################
# Histogramme distribution aire 
###############################

"""
    histogram_area_classes(n, W, H)

Outil de calibrage : génère `n` grilles W×H et affiche la distribution des rectangles
par classe d'aire, en pourcentage du nombre de rectangles et de la surface totale couverte.

Permet de vérifier empiriquement que `AREA_CLASSES` produit bien la répartition souhaitée.

# Arguments
- `n::Int` : nombre de grilles à générer pour l'échantillonnage
- `W::Int` : largeur des grilles générées
- `H::Int` : hauteur des grilles générées

# Retourne
Un quadruplet `(rect_counts, area_sums, total_rects, total_area)` où :
- `rect_counts`  : `Dict{String,Int}` — nombre de rectangles par classe
- `area_sums`    : `Dict{String,Int}` — somme des aires par classe
- `total_rects`  : nombre total de rectangles sur toutes les grilles
- `total_area`   : surface totale couverte (= n × W × H)
"""
function histogram_area_classes(n::Int, W::Int, H::Int)
    area_classes = [
        (2, 5, "2–5"),
        (6, 10, "6–10"),
        (11, 15, "11–15"),
        (16, 25, "16–25"),
        (26, 40, "26–40"),
        (41, typemax(Int), "41+")
    ]

    rect_counts = Dict{String,Int}()
    area_sums = Dict{String,Int}()

    for (_,_,label) in area_classes
        rect_counts[label] = 0
        area_sums[label] = 0
    end

    total_rects = 0
    total_area = 0

    for i in 1:n
        rects = generate_rectangles_structured(W, H)

        for r in rects
            A = r.w * r.h
            total_rects += 1
            total_area += A

            for (amin,amax,label) in area_classes
                if amin <= A <= amax
                    rect_counts[label] += 1
                    area_sums[label] += A
                    break
                end
            end
        end
    end

    println("=== HISTOGRAMME PAR CLASSES D'AIRE SUR $n GRILLES $W x $H ===")
    println("→ Pourcentage de rectangles")
    println("→ Pourcentage de surface totale\n")

    for (_,_,label) in area_classes
        pct_rects = 100 * rect_counts[label] / total_rects
        pct_area  = 100 * area_sums[label] / total_area

        println("Classe $label :")
        println("   Rectangles : $(round(pct_rects, digits=2))%")
        println("   Surface    : $(round(pct_area, digits=2))%")
    end

    return rect_counts, area_sums, total_rects, total_area
end

end
