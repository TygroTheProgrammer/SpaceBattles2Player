require 'socket'
require 'json'

server = TCPServer.new 9090

class Map
  def initialize(max_width=32, max_height=32)
    @max_width = max_width
    @max_height = max_height
    @map = Array.new(2*@max_width) { Array.new(2*@max_height) { nil } }
  end

  def update_tile(tile)
    # puts tile.inspect
    # puts tile['x']+@max_width
    # puts tile['y']+@max_height
    @map[tile['x']+@max_width][tile['y']+@max_height] = tile
  end

  def at(x,y)
    col = @map[x+@max_width]
    col[y+@max_height] if col
  end

  def pretty(units)
    # TODO draw units?
    33.times { puts }
    puts("="*66)
    @map.transpose.each.with_index do |rows, i|
      STDOUT.write "|"
      rows.each.with_index do |v, j|
        if v.nil?
          STDOUT.write "?"
        elsif v['resources']
          STDOUT.write "$"
        elsif v['blocked']
          STDOUT.write "X"
        else
          STDOUT.write " "
        end
      end
      STDOUT.puts "|"
    end
    puts("="*66)
    all_units = units.values
    base = all_units.find{|u| u['type'] == 'base'}
    puts "PLAYER RES: #{base['resource']}" if base
    puts "UNIT RES: #{((all_units-[base]).compact).map{|u|u['resource']}.compact.reduce(0, &:+)}"
  end
end

require_relative './server/lib/vec'
DIR_VECS = {
  'N' => vec(0,-1),
  'S' => vec(0,1),
  'W' => vec(-1,0),
  'E' => vec(1,0),
}
def resource_adjacent_to(map, base, unit_info)
  x = unit_info['x']
  y = unit_info['y']

  tile = map.at(x,y)
  if tile
    DIR_VECS.each do |dir, dir_vec|
      xx = x + dir_vec.x
      yy = y + dir_vec.y

      unless base.nil? || (base['x'] == xx && base['y'] == yy)
        tile = map.at(xx,yy)
        # XXX will this allow stealing from other player's bases?
        return dir if tile && tile['resources']
      end
    end
  end
  nil
end

def gather_command(dir, id)
  cmd = {
    command: "GATHER",
    unit: id,
    dir: dir
  }
end

def move_command(outstanding_unit_cmds, id)
  outstanding_unit_cmds[id] = :move
  dir = ["N","S","E","W"].sample
  cmd = {
    command: "MOVE",
    unit: id,
    dir: dir
  }
end

loop do
  server_connection = server.accept    # Wait for a server_connection to connect
  units = {}
  outstanding_unit_cmds = {}
  map = Map.new

	while msg = server_connection.gets
    json = JSON.parse(msg)
    # puts json

    @player_id ||= json['player']

    cmds = []
    cmd_msg = {commands: cmds, player_id: @player_id}

    tile_updates = json['tile_updates']
    if tile_updates || json['unit_updates']
      if tile_updates
        tile_updates.each do |tu|
          map.update_tile tu
        end
      end

      map.pretty(units)
    end

    unit_updates = {}
    (json['unit_updates'] || []).each do |uu|
      unit_updates[uu['id']] = uu
    end

    unit_ids = unit_updates.keys | units.keys
    unit_ids.each do |id|
      if uu = unit_updates[id]
        units[id] =  uu
        if uu['status'] == 'moving'
          outstanding_unit_cmds.delete(id) if outstanding_unit_cmds[id] == :move
        elsif uu['status'] == 'idle'

          base = units.values.find{|u| u['type'] == 'base'}
          res_dir = resource_adjacent_to(map, base, uu)
          if res_dir && (!uu['resource'] || uu['resource'] == 0)
            cmds << gather_command(res_dir, id)
          else
            cmds << move_command(outstanding_unit_cmds, id)
          end
        end
      end
      if outstanding_unit_cmds[id] == :move
        cmds << move_command(outstanding_unit_cmds, id)
      end
    end

    server_connection.puts(cmd_msg.to_json) unless cmds.empty?

  end

  server_connection.close
end
