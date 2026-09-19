local position = require("tour.position")
local text = require("tour.util.text")
local gutter = require("tour.render.gutter")
local api = vim.api
local M = {}
local presentation = api.nvim_create_namespace("tour.presentation")
local tracking = api.nvim_create_namespace("tour.tracking")

-- Use the theme's foreground and comment colors, keeping prose readable
-- without giving every note the theme's saturated SpecialComment accent.
local function prose(group, weight, fallback, italic)
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false }).fg
  local comment = api.nvim_get_hl(0, { name = "Comment", link = false }).fg
  if not normal or not comment then
    api.nvim_set_hl(0, group, { default = true, link = fallback })
    return
  end
  local color = 0
  for _, shift in ipairs({ 0, 8, 16 }) do
    local base = 2 ^ shift
    local a, b = math.floor(normal / base) % 256, math.floor(comment / base) % 256
    color = color + math.floor(a * weight + b * (1 - weight) + 0.5) * base
  end
  api.nvim_set_hl(0, group, { default = true, fg = color, italic = italic })
end

function M.highlights()
  for group, link in pairs({
    TourHeader = "Title",
    TourRange = "Title",
    TourHighlight = "IncSearch",
  }) do
    api.nvim_set_hl(0, group, { default = true, link = link })
  end
  prose("TourDescription", 0.85, "Normal", false)
  prose("TourAnnotation", 0.65, "Comment", true)
end

function M.clear(runtime)
  gutter.clear()
  if runtime and api.nvim_buf_is_valid(runtime.buf) then
    api.nvim_buf_clear_namespace(runtime.buf, presentation, 0, -1)
    api.nvim_buf_clear_namespace(runtime.buf, tracking, 0, -1)
  end
end

local function track(buf, range)
  local row, col, opts = position.extmark(range)
  return api.nvim_buf_set_extmark(buf, tracking, row, col, opts)
end

function M.attach(buf, step)
  local runtime = { buf = buf, primary = track(buf, step.location.range), notes = {} }
  for i, note in ipairs(step.annotations) do
    runtime.notes[i] = track(buf, note.range)
  end
  return runtime
end

function M.reconcile(runtime, step)
  if not runtime or not api.nvim_buf_is_loaded(runtime.buf) then
    return
  end
  local lines = api.nvim_buf_get_lines(runtime.buf, 0, -1, false)
  local function read(id, range)
    local mark = api.nvim_buf_get_extmark_by_id(runtime.buf, tracking, id, { details = true })
    if #mark > 0 then
      local function point(row, col)
        local p = position.point(row, col)
        p.line = math.min(p.line, #lines)
        p.col = math.min(p.col, #lines[p.line])
        return p
      end
      range.start = point(mark[1], mark[2])
      range["end"] = point(mark[3].end_row, mark[3].end_col)
      if
        range["end"].line < range.start.line
        or (range["end"].line == range.start.line and range["end"].col < range.start.col)
      then
        range["end"] = vim.deepcopy(range.start)
      end
    end
  end
  read(runtime.primary, step.location.range)
  for i, id in ipairs(runtime.notes) do
    read(id, step.annotations[i].range)
  end
  local row = position.row(step.location.range.start.line)
  local anchor = vim.trim(api.nvim_buf_get_lines(runtime.buf, row, row + 1, false)[1] or "")
  if not step.location.anchor or not anchor:find(step.location.anchor, 1, true) then
    step.location.anchor = anchor ~= "" and anchor or nil
  end
end

local function viewport(buf, maximum)
  local width = maximum
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    width = math.min(width, api.nvim_win_get_width(win) - info.textoff)
  end
  return math.max(1, width)
end

function M.draw(runtime, data, config)
  local buf = runtime.buf
  if not api.nvim_buf_is_loaded(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, presentation, 0, -1)
  local step = data.steps[data.current_step]
  local range = step.location.range
  gutter.update(buf, range)
  local width = viewport(buf, config.max_width)
  local header = ("Tour %d/%d · %s"):format(
    data.current_step,
    #data.steps,
    text.step_title(step.title, data.current_step)
  )
  local lines = text.lines(header, width, "", "TourHeader")
  if step.description and step.description ~= "" then
    lines[#lines + 1] = { { "", "TourDescription" } }
    vim.list_extend(lines, text.lines(step.description, width, "", "TourDescription"))
  end
  lines[#lines + 1] = { { "", "TourDescription" } }
  api.nvim_buf_set_extmark(buf, presentation, position.row(range.start.line), 0, {
    virt_lines = lines,
    virt_lines_above = true,
    virt_lines_overflow = "wrap",
    priority = 200,
  })
  for _, note in ipairs(step.annotations) do
    local start_row, start_col, highlight = position.extmark(note.range)
    if note.placement == "highlight" then
      highlight.hl_group = "TourHighlight"
      highlight.priority = 120
      api.nvim_buf_set_extmark(buf, presentation, start_row, start_col, highlight)
    else
      local below_row = position.row(position.last_line(note.range))
      local source_line = api.nvim_buf_get_lines(buf, start_row, start_row + 1, false)[1]
      local indent =
        math.min(vim.fn.strdisplaywidth(source_line:match("^%s*")), math.floor(width / 4))
      local prefix = width >= indent + 5 and string.rep(" ", indent) .. "  › " or ""
      local continuation = string.rep(" ", vim.fn.strdisplaywidth(prefix))
      if note.placement == "above" or note.placement == "below" then
        api.nvim_buf_set_extmark(
          buf,
          presentation,
          note.placement == "above" and start_row or below_row,
          0,
          {
            virt_lines = text.lines(note.text, width, prefix, "TourAnnotation", continuation),
            virt_lines_above = note.placement == "above",
            virt_lines_overflow = "wrap",
          }
        )
      else
        -- A short first line attaches to the expression/EOL. Overflow goes
        -- into virtual lines so it is readable even with 'nowrap'.
        local end_row = below_row
        local source = api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1]
        local end_col = position.last_line(note.range) == note.range["end"].line
            and note.range["end"].col
          or #source
        local offset = note.placement == "inline" and vim.fn.strdisplaywidth(source:sub(1, end_col))
          or vim.fn.strdisplaywidth(source)
        local available = width - offset - 3
        local first, rest
        if available >= 8 then
          rest = text.wrap(note.text, width - vim.fn.strdisplaywidth(prefix), available)
          first = table.remove(rest, 1)
        else
          rest = text.wrap(note.text, math.max(1, width - vim.fn.strdisplaywidth(prefix)))
        end
        local mark = { virt_lines_overflow = "wrap" }
        if first then
          mark.virt_text = { { " · " .. first, "TourAnnotation" } }
          mark.virt_text_pos = note.placement
        end
        if #rest > 0 then
          mark.virt_lines = {}
          for i, line in ipairs(rest) do
            local leader = not first and i == 1 and prefix or continuation
            mark.virt_lines[#mark.virt_lines + 1] = { { leader .. line, "TourAnnotation" } }
          end
        end
        api.nvim_buf_set_extmark(buf, presentation, end_row, end_col, mark)
      end
    end
  end
end

return M
