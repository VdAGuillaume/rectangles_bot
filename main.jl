using Raylib;
using StatsBase: countmap;
using Serialization;

include("./gridfbot_commenté.jl");
using .Grid;
import .Grid: Rectangle, GameState;

include("./botf_code.jl");

Base.hash(r::Rectangle, h::UInt) = hash((r.x, r.y, r.w, r.h), h)
Base.:(==)(a::Rectangle, b::Rectangle) = (a.x, a.y, a.w, a.h) == (b.x, b.y, b.w, b.h)

const screen_w::Int64 = 1280;
const screen_h::Int64 = 720;
const margin_h::Int64 = 50;
const HOME::Int64 = -180;
const filesave = "./save.jls";

drawRect(rec::Rectangle, color) = Raylib.DrawRectangle(rec.x, rec.y, rec.w, rec.h, color);
drawRectLines(rec::Rectangle, color) = Raylib.DrawRectangleLines(rec.x, rec.y, rec.w, rec.h, color);

function drawRectLinesThick(rec::Rectangle, thickness::Int64, color)
	for i in 0:thickness-1
		drawRectLines(Rectangle(rec.x + i, rec.y + i, rec.w - 2*i, rec.h - 2*i), color);
	end
end

function drawTextCentered(text::String, x::Int64, y::Int64, w::Int64, h::Int64, font_size::Int64, color)
	text_w::Int64 = Raylib.MeasureText(text, font_size);
	text_x::Int64 = x + div(w - text_w, 2);
	text_y::Int64 = y + div(h - font_size, 2);
	Raylib.DrawText(text, text_x, text_y, font_size, color);
end

function isPointInRect(point, rec::Rectangle)
	return point.x >= rec.x && point.x <= rec.x + rec.w && point.y >= rec.y && point.y <= rec.y + rec.h;
end

function tileToRects(w::Int64, h::Int64)
	case_size = min(div(screen_w - 2*margin_w, w), div(screen_h - 2*margin_h, h));
	x0 = div(screen_w - w * case_size, 2);
	y0 = div(screen_h - h * case_size, 2);
	return [Rectangle(x0 + (i-1)*case_size, y0 + (j-1)*case_size, case_size, case_size) for i in 1:w, j in 1:h];
end

function mouseToTile(pos, w::Int64, h::Int64)
	case_size = min(div(screen_w - 2*margin_w, w), div(screen_h - 2*margin_h, h));
	x0 = div(screen_w - w * case_size, 2);
	y0 = div(screen_h - h * case_size, 2);
	tile_x = div(pos.x - x0, case_size) + 1;
	tile_y = div(pos.y - y0, case_size) + 1;
	if tile_x < 1 || tile_x > w || tile_y < 1 || tile_y > h
		return (-1, -1);
	end
	return (tile_x, tile_y);
end

function isRectValid(rec::Rectangle, grid::Matrix{Int64})
	num_count = 0;
	for i in rec.x:rec.x+rec.w-1, j in rec.y:rec.y+rec.h-1
		if grid[j, i] != 0
			num_count += 1;
			if grid[j, i] != rec.w * rec.h || num_count > 1
				return false;
			end
		end
	end
	return num_count != 0;
end

function areRectsOverlapping(rec1::Rectangle, rec2::Rectangle)
	return !(rec1.x + rec1.w <= rec2.x || rec2.x + rec2.w <= rec1.x || rec1.y + rec1.h <= rec2.y || rec2.y + rec2.h <= rec1.y);
end

function isGameWon(state::GameState)
	area = 0;
	for rec in state.rects
		if(!isRectValid(rec, state.grid))
			return false;
		end
		area += rec.w * rec.h;
	end
	return area == state.w * state.h;
end

function saveState(state::GameState)
	serialize(filesave, state);
end

function loadState()
	return deserialize(filesave);
end

const button_nbr = 7;
const button_w::Int64 = 100;
const button_h::Int64 = 50;
const exit_x::Int64 = (screen_w - 300) / 2;
const start_dx::Int64  = 40;
const start_tot::Int64 = button_nbr * button_w + 6 * start_dx;
const start_x0::Int64  = (screen_w - start_tot) / 2;
const start_y0::Int64  = 200;
const button_start = [Rectangle(start_x0 + (i-1) * (button_w + start_dx), start_y0, button_w, button_h) for i in 1:button_nbr];
const button_restore = Rectangle(exit_x, 520, 300, button_h);
const custom_rect = Rectangle(500, 350, screen_w - 1000, button_h);
const num_keys = [Raylib.KEY_ZERO, Raylib.KEY_ONE, Raylib.KEY_TWO, Raylib.KEY_THREE, Raylib.KEY_FOUR, Raylib.KEY_FIVE, Raylib.KEY_SIX, Raylib.KEY_SEVEN, Raylib.KEY_EIGHT, Raylib.KEY_NINE];
const kp_keys  = [Raylib.KEY_KP_0, Raylib.KEY_KP_1, Raylib.KEY_KP_2, Raylib.KEY_KP_3, Raylib.KEY_KP_4, Raylib.KEY_KP_5, Raylib.KEY_KP_6, Raylib.KEY_KP_7, Raylib.KEY_KP_8, Raylib.KEY_KP_9];

function returnToHome!(state::GameState)
	global bot_solution, bot_anim_index, bot_animating, bot_anim_done;
	state.w = HOME;
	state.h = HOME;
	state.grid = Matrix{Int64}(undef, 0, 0);
	empty!(state.rects);
	empty!(state.win_rects);
	state.focus[1] = -1;
	state.focus[2] = -1;
	state.hover[1] = -1;
	state.hover[2] = -1;
	state.won = false;
	state.custom_str = "";
	bot_solution   = Rectangle[];
	bot_anim_index = 0;
	bot_animating  = false;
	bot_anim_done  = false;
end

function updateHome!(state::GameState)
	if(Raylib.IsMouseButtonPressed(Integer(Raylib.MOUSE_LEFT_BUTTON)))
		mouse_pos = Raylib.GetMousePosition();
		for i in 1:length(button_start)
			if isPointInRect(mouse_pos, button_start[i])
				state.w = 5 + 2 * i;
				state.h = 5 + 2 * i;
				return;
			end
		end
		if isPointInRect(mouse_pos, button_restore)
			if(isfile(filesave))
				loaded = loadState();
				state.w          = loaded.w;
				state.h          = loaded.h;
				state.grid       = loaded.grid;
				state.rects      = loaded.rects;
				state.win_rects  = loaded.win_rects;
				state.focus      = [-1, -1];
				state.hover      = [-1, -1];
				state.won        = false;
				state.custom_str = loaded.custom_str;
				return;
			end
		end
	end
	pressed = Raylib.GetKeyPressed();
	if(pressed != 0)
		if(pressed == Integer(Raylib.KEY_BACKSPACE) && !isempty(state.custom_str))
			state.custom_str = state.custom_str[1:end-1];
		elseif(pressed in num_keys || pressed == Integer(Raylib.KEY_X))
			state.custom_str *= lowercase(Char(pressed));
		elseif(pressed in kp_keys)
			state.custom_str *= lowercase(Char(pressed - Integer(Raylib.KEY_KP_0) + Integer(Raylib.KEY_ZERO)));
		elseif((pressed == Integer(Raylib.KEY_ENTER) || pressed == Integer(Raylib.KEY_KP_ENTER)) && occursin('x', state.custom_str))
			parts = split(state.custom_str, 'x');
			if length(parts) == 2
				state.w = parse(Int64, parts[1]);
				state.h = parse(Int64, parts[2]);
			else
				returnToHome!(state);
			end
		end
	end
end

function drawHome(state::GameState)
	Raylib.BeginDrawing();
	Raylib.ClearBackground(Raylib.RAYWHITE);
	drawTextCentered("Rectangles", 0, 75, screen_w, 50, 30, Raylib.BLACK);
	drawTextCentered("Select a grid size", 0, 110, screen_w, 50, 30, Raylib.BLACK);
	for i in 1:button_nbr
		drawRect(button_start[i], Raylib.BLACK);
		label = "$(5+2*i)" * "x" * "$(5+2*i)";
		drawTextCentered(label, button_start[i].x, button_start[i].y, button_start[i].w, button_start[i].h, 20, Raylib.RAYWHITE);
	end
	drawRectLines(custom_rect, Raylib.BLACK);
	if(state.custom_str == "")
		drawTextCentered("Custom size (e.g. 180x180)", custom_rect.x, custom_rect.y, custom_rect.w, custom_rect.h, 20, Raylib.GRAY);
	else
		drawTextCentered("$(state.custom_str)", custom_rect.x, custom_rect.y, custom_rect.w, custom_rect.h, 20, Raylib.GRAY);
	end
	drawRect(button_restore, Raylib.BLACK);
	drawTextCentered("Restore last game", button_restore.x, button_restore.y, button_restore.w, button_restore.h, 20, Raylib.RAYWHITE);
	Raylib.EndDrawing();
end

const margin_w = 300;

const button_solve_w::Int64 = 200;
const button_solve_h::Int64 = 50;
const button_solve = Rectangle(div(margin_w - button_solve_w, 2), screen_h - 120, button_solve_w, button_solve_h);

bot_solution   = Rectangle[];
bot_anim_index = 0;
bot_animating  = false;
bot_anim_done  = false;
const BOT_ANIM_DELAY = 0.35;
bot_last_time  = 0.0;

const button_continue_w::Int64 = 220;
const button_continue_h::Int64 = 60;
const button_continue = Rectangle(div(screen_w - button_continue_w, 2), div(screen_h - button_continue_h, 2) + 60, button_continue_w, button_continue_h);

function resetGame!(state::GameState)
	global bot_solution, bot_anim_index, bot_animating, bot_anim_done;
	empty!(state.rects);
	state.custom_str = "";
	bot_solution   = Rectangle[];
	bot_anim_index = 0;
	bot_animating  = false;
	bot_anim_done  = false;
end

function updateGame!(state::GameState)
	global bot_solution, bot_anim_index, bot_animating, bot_anim_done, bot_last_time;

	mouse_pos = Raylib.GetMousePosition();
	state.hover[1], state.hover[2] = mouseToTile(mouse_pos, state.w, state.h);

	if bot_animating
		now = Raylib.GetTime();
		if now - bot_last_time >= BOT_ANIM_DELAY && bot_anim_index < length(bot_solution)
			bot_anim_index += 1;
			push!(state.rects, bot_solution[bot_anim_index]);
			bot_last_time = now;
		end
		if bot_anim_index >= length(bot_solution)
			bot_animating = false;
			bot_anim_done = true;
		end
		return;
	end

	if bot_anim_done
		if Raylib.IsMouseButtonPressed(Integer(Raylib.MOUSE_LEFT_BUTTON))
			if isPointInRect(Raylib.GetMousePosition(), button_continue)
				bot_anim_done = false;
				state.won = true;
			end
		end
		return;
	end

	if(Raylib.IsMouseButtonReleased(Integer(Raylib.MOUSE_LEFT_BUTTON)))
		if state.hover[1] != -1 && state.hover[2] != -1 && state.focus[1] != -1 && state.focus[2] != -1 && state.focus != state.hover
			new_rect = Rectangle(min(state.focus[1], state.hover[1]), min(state.focus[2], state.hover[2]), 1 + abs(state.hover[1] - state.focus[1]), 1 + abs(state.hover[2] - state.focus[2]));
			for rec in state.rects
				if areRectsOverlapping(rec, new_rect)
					filter!(r -> !areRectsOverlapping(rec, r), state.rects);
				end
			end
			push!(state.rects, new_rect);
		end
	elseif(Raylib.IsMouseButtonUp(Integer(Raylib.MOUSE_LEFT_BUTTON)))
		state.focus[1] = state.hover[1];
		state.focus[2] = state.hover[2];
	end

	if(Raylib.IsKeyPressed(Integer(Raylib.KEY_R)))
		resetGame!(state);
	end

	if(Raylib.IsKeyPressed(Integer(Raylib.KEY_H)))
		returnToHome!(state);
	end

	if(Raylib.IsMouseButtonPressed(Integer(Raylib.MOUSE_LEFT_BUTTON)))
		if isPointInRect(Raylib.GetMousePosition(), button_solve)
			solution = solve(state);
			if solution !== nothing
				empty!(state.rects);
				bot_solution   = solution;
				bot_anim_index = 0;
				bot_animating  = true;
				bot_anim_done  = false;
				bot_last_time  = Raylib.GetTime();
			end
		end
	end
end

function drawGame(state::GameState)
	global bot_animating, bot_anim_done;

	Raylib.BeginDrawing();
	Raylib.ClearBackground(Raylib.RAYWHITE);

	tile_rects = tileToRects(state.w, state.h);
	total_w = state.w * tile_rects[1, 1].w;

	for i in 1:state.w
		for j in 1:state.h
			drawRectLines(tile_rects[i, j], Raylib.BLACK);
			if(state.grid[j, i] > 0)
				drawTextCentered("$(state.grid[j, i])", tile_rects[i, j].x, tile_rects[i, j].y, tile_rects[i, j].w, tile_rects[i, j].h, 20, Raylib.BLACK);
			end
		end
	end

	for rec in state.rects
		real_rect = Rectangle(
			tile_rects[rec.x, rec.y].x,
			tile_rects[rec.x, rec.y].y,
			rec.w * tile_rects[1,1].w,
			rec.h * tile_rects[1,1].h
		);
		if(isRectValid(rec, state.grid))
			drawRect(real_rect, Raylib.Fade(Raylib.DARKGRAY, 0.5));
		end
		drawRectLinesThick(real_rect, 2, Raylib.RED);
	end

	if(!bot_animating && !bot_anim_done)
		if(Raylib.IsMouseButtonDown(Integer(Raylib.MOUSE_LEFT_BUTTON)) && state.focus[1] != -1 && state.focus[2] != -1 && state.hover[1] != -1 && state.hover[2] != -1 && state.focus != state.hover)
			dragged = Rectangle(
				min(state.focus[1], state.hover[1]),
				min(state.focus[2], state.hover[2]),
				abs(state.hover[1] - state.focus[1]) + 1,
				abs(state.hover[2] - state.focus[2]) + 1
			);
			dragged_rect = Rectangle(
				tile_rects[dragged.x, dragged.y].x,
				tile_rects[dragged.x, dragged.y].y,
				dragged.w * tile_rects[1, 1].w,
				dragged.h * tile_rects[1, 1].h
			);
			drawRectLinesThick(dragged_rect, 4, Raylib.RED);
			drawTextCentered("$(dragged.w)x$(dragged.h)=$(dragged.w * dragged.h)", margin_w + total_w, 0, margin_w, screen_h, 20, Raylib.GRAY);
		end
		drawTextCentered("Press R to reset\n\nPress H\nto return to home screen\n\nHold S\nto see solution", 0, 0, margin_w, screen_h - 150, 20, Raylib.GRAY);
		drawRect(button_solve, Raylib.BLACK);
		drawTextCentered("Solve with bot", button_solve.x, button_solve.y, button_solve.w, button_solve.h, 18, Raylib.RAYWHITE);

		if Raylib.IsKeyDown(Integer(Raylib.KEY_S))
			for rec in state.win_rects
				sol_rect = Rectangle(
					tile_rects[rec.x, rec.y].x,
					tile_rects[rec.x, rec.y].y,
					rec.w * tile_rects[1,1].w,
					rec.h * tile_rects[1,1].h
				);
				drawRect(sol_rect, Raylib.Fade(Raylib.BLUE, 0.25));
				drawRectLinesThick(sol_rect, 2, Raylib.Fade(Raylib.BLUE, 0.75));
			end
		end
	end

	if bot_anim_done
		Raylib.DrawRectangle(0, 0, screen_w, screen_h, Raylib.Fade(Raylib.BLACK, 0.45));
		drawTextCentered("Puzzle solved by the bot!", 0, 0, screen_w, div(screen_h, 2) - 20, 30, Raylib.RAYWHITE);
		drawRect(button_continue, Raylib.RAYWHITE);
		drawTextCentered("Continue", button_continue.x, button_continue.y, button_continue.w, button_continue.h, 24, Raylib.BLACK);
	end

	Raylib.EndDrawing();
end

function updateWin!(state::GameState)
	if(Raylib.GetKeyPressed() != 0)
		returnToHome!(state);
	end
end

function drawWinScreen()
	Raylib.BeginDrawing();
	Raylib.ClearBackground(Raylib.RAYWHITE);
	drawTextCentered("You won! Press any key to return to home screen", 0, 0, screen_w, screen_h, 30, Raylib.BLACK);
	Raylib.EndDrawing();
end

function main()
	state::GameState = GameState(HOME, HOME, Matrix{Int64}(undef, 0, 0), Rectangle[], Rectangle[], [-1, -1], [-1, -1], false, "");

	Raylib.InitWindow(screen_w, screen_h, "Rectangles");
	Raylib.SetTargetFPS(60);
	Raylib.SetTraceLogLevel(Integer(Raylib.LOG_ERROR));

	while(!Raylib.WindowShouldClose())
		if(state.w == HOME)
			updateHome!(state);
			drawHome(state);
			if(state.w > 0 && isempty(state.rects) && isempty(state.win_rects))
				state = generate_puzzle(state.w, state.h);
			end

		elseif(state.won)
			updateWin!(state);
			drawWinScreen();

		elseif(state.w > 0)
			updateGame!(state);
			if(state.w > 0)
				drawGame(state);
				if(!bot_animating && !bot_anim_done)
					state.won = isGameWon(state);
				end
			end
			if(state.won)
				sleep(0.180);
			end
		end
	end

	if(!state.won && state.w > 0)
		saveState(state);
	end

	Raylib.CloseWindow();
end

main();
