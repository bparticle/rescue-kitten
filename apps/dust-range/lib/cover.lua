local Cover = {}
local min, max, abs, sqrt = math.min, math.max, math.abs, math.sqrt

local layouts = {
  {
    {left=405, right=425, top=287, bottom=309},
    {left=472, right=493, top=335, bottom=357},
  },
  {
    {left=377, right=395, top=268, bottom=291},
    {left=437, right=458, top=311, bottom=329},
    {left=507, right=528, top=349, bottom=372},
  },
  {
    {left=384, right=411, top=307, bottom=331},
    {left=465, right=486, top=265, bottom=287},
    {left=486, right=506, top=352, bottom=376},
  },
}
local graphs = setmetatable({}, {__mode="k"})

local function span(position, direction, low, high, near, far)
  if direction == 0 then
    if position >= low and position <= high then return near, far end
    return
  end
  local enter, exit = (low-position)/direction, (high-position)/direction
  if enter > exit then enter, exit = exit, enter end
  near, far = max(near, enter), min(far, exit)
  if near <= far then return near, far end
end

-- First intersection with a closed rectangle, in the same units as reach.
function Cover.entry(blocks, x, y, dx, dy, reach, padding)
  if reach <= 0 then return end
  local best, hit = reach, nil
  for _, block in ipairs(blocks) do
    local near, far = span(x, dx, block.left-padding, block.right+padding, 0, best)
    if near then
      local entry = span(y, dy, block.top-padding, block.bottom+padding, near, far)
      if entry then best, hit = entry, block end
    end
  end
  if hit then return best, hit end
end

function Cover.can_stand(blocks, x, y, padding)
  for _, block in ipairs(blocks) do
    if x >= block.left-padding and x <= block.right+padding
      and y >= block.top-padding and y <= block.bottom+padding then return false end
  end
  return true
end

function Cover.layout(phase, previous, x, y, radius)
  for offset = 0, #layouts-1 do
    local layout = layouts[(phase+offset)%#layouts+1]
    if layout ~= previous and Cover.can_stand(layout,x,y,radius) then return layout end
  end
  return previous
end

function Cover.slide(blocks, x, y, next_x, next_y, radius)
  local step_x = next_x-x
  if step_x ~= 0 then
    local direction = step_x > 0 and 1 or -1
    local hit = Cover.entry(blocks, x, y, direction, 0, abs(step_x), radius)
    if hit then next_x = x + direction*max(0, hit-0.05) end
  end
  local step_y = next_y-y
  if step_y ~= 0 then
    local direction = step_y > 0 and 1 or -1
    local hit = Cover.entry(blocks, next_x, y, 0, direction, abs(step_y), radius)
    if hit then next_y = y + direction*max(0, hit-0.05) end
  end
  return next_x, next_y
end

local function graph_for(blocks, radius)
  local sizes = graphs[blocks]
  if not sizes then sizes = {}; graphs[blocks] = sizes end
  local graph = sizes[radius]
  if graph then return graph end

  local margin = radius+2
  local nodes = {}
  for _, block in ipairs(blocks) do
    for side_x = -1, 1, 2 do
      local x = side_x < 0 and block.left-margin or block.right+margin
      for side_y = -1, 1, 2 do
        local y = side_y < 0 and block.top-margin or block.bottom+margin
        if Cover.can_stand(blocks,x,y,radius) then nodes[#nodes+1] = {x=x, y=y, edges={}} end
      end
    end
  end
  for i = 1, #nodes-1 do
    local a = nodes[i]
    for j = i+1, #nodes do
      local b = nodes[j]
      local dx, dy = b.x-a.x, b.y-a.y
      if not Cover.entry(blocks,a.x,a.y,dx,dy,1,radius) then
        local distance = sqrt(dx*dx+dy*dy)
        a.edges[j], b.edges[i] = distance, distance
      end
    end
  end
  graph = {nodes=nodes, costs={}, visited={}}
  sizes[radius] = graph
  return graph
end

-- An enemy may need more room beside a block than the player it is chasing.
local function open_goal(blocks, x, y, radius)
  for _, block in ipairs(blocks) do
    local left, right = block.left-radius, block.right+radius
    local top, bottom = block.top-radius, block.bottom+radius
    if x >= left and x <= right and y >= top and y <= bottom then
      local horizontal = min(x-left, right-x)
      local vertical = min(y-top, bottom-y)
      if horizontal <= vertical then x = x-left <= right-x and left-0.1 or right+0.1
      else y = y-top <= bottom-y and top-0.1 or bottom+0.1 end
    end
  end
  return x, y
end

local function route_costs(blocks, graph, x, y, radius)
  if graph.target_x == x and graph.target_y == y then return graph.costs end
  graph.target_x, graph.target_y = x, y
  local nodes, costs, visited = graph.nodes, graph.costs, graph.visited
  for index, node in ipairs(nodes) do
    local dx, dy = x-node.x, y-node.y
    visited[index] = false
    costs[index] = Cover.entry(blocks,node.x,node.y,dx,dy,1,radius) and math.huge or sqrt(dx*dx+dy*dy)
  end

  -- Work backwards from the goal. Enemies with the same radius can reuse the costs.
  for _ = 1, #nodes do
    local closest, cost = nil, math.huge
    for index = 1, #nodes do
      if not visited[index] and costs[index] < cost then closest, cost = index, costs[index] end
    end
    if not closest then break end
    visited[closest] = true
    for index, distance in pairs(nodes[closest].edges) do
      costs[index] = min(costs[index], cost+distance)
    end
  end
  return costs
end

function Cover.waypoint(blocks, x, y, target_x, target_y, radius, previous_x, previous_y)
  if not Cover.entry(blocks,x,y,target_x-x,target_y-y,1,radius) then return end
  if previous_x then
    local dx, dy = previous_x-x, previous_y-y
    if dx*dx+dy*dy > 1 and not Cover.entry(blocks,x,y,dx,dy,1,radius) then return previous_x, previous_y end
  end
  local goal_x, goal_y = open_goal(blocks,target_x,target_y,radius)
  if not Cover.entry(blocks,x,y,goal_x-x,goal_y-y,1,radius) then return goal_x, goal_y end

  local graph = graph_for(blocks,radius)
  local costs = route_costs(blocks,graph,goal_x,goal_y,radius)
  local waypoint, nearest = nil, math.huge
  for index, node in ipairs(graph.nodes) do
    local dx, dy = node.x-x, node.y-y
    local travel = dx*dx + dy*dy
    local cost = sqrt(travel)+costs[index]
    if travel > 0.01 and cost < nearest and not Cover.entry(blocks,x,y,dx,dy,1,radius) then
      waypoint, nearest = node, cost
    end
  end
  if waypoint then return waypoint.x, waypoint.y end
end

return Cover
