# The pillbox is a map object, and thus a slightly special case of world object.

{min, max, sqrt,
 round, ceil, PI
 cos, sin, atan2} = Math
{TILE_SIZE_WORLD} = require '../constants'
WorldObject       = require '../world_object'
Shell             = require './shell'


class SimPillbox extends WorldObject
  charId: 'p'

  # This is a MapObject; it is constructed differently on the authority.
  constructor: (sim_or_map, x, y, @owner_idx, @armour, @speed) ->
    if arguments.length == 1
      @sim = sim_or_map
    else
      @x = (x + 0.5) * TILE_SIZE_WORLD; @y = (y + 0.5) * TILE_SIZE_WORLD

    @on 'spawn', =>
      @coolDown = 32
      @reload = 0

    # After initialization on client and server set-up the cell reference.
    @on 'anySpawn', =>
      @updateCell()

    # Keep our non-synchronized attributes up-to-date on the client.
    @on 'netUpdate', (changes) =>
      if changes.hasOwnProperty('x') or changes.hasOwnProperty('y')
        @updateCell()
      if changes.hasOwnProperty('owner')
        @owner_idx = if @owner then @owner.$.tank_idx else 255
        @cell?.retile()

  # Helper that updates the cell reference, and ensures a back-reference as well.
  updateCell: ->
    if @cell
      delete @cell.pill
      @cell.retile()
    if @x? and @y?
      @cell = @sim.map.cellAtWorld(@x, @y)
      @cell.pill = this
      @cell.retile()
    else
      @cell = null

  # The state information to synchronize.
  serialization: (isCreate, p) ->
    p 'H', 'x'
    p 'H', 'y'

    p 'T', 'owner'
    p 'f', 'haveTarget'
    p 'B', 'armour'
    p 'B', 'speed'
    p 'B', 'coolDown'
    p 'B', 'reload'

  update: ->
    return @haveTarget = no if @armour == 0

    @reload = min(@speed, @reload + 1)
    if --@coolDown == 0
      @coolDown = 32
      @speed = min(100, @speed + 1)
    return unless @reload >= @speed

    target = null; distance = Infinity
    for tank in @sim.tanks when tank.armour != 255 and not @owner?.$.isAlly(tank)
      dx = tank.x - @x; dy = tank.y - @y
      d = sqrt(dx*dx + dy*dy)
      if d <= 2048 and d < distance
        target = tank; distance = d
    return @haveTarget = no unless target

    # On the flank from idle to targetting, don't fire immediatly.
    if @haveTarget
      # FIXME: This code needs some helpers, taken from Tank.
      rad = (256 - target.getDirection16th() * 16) * 2 * PI / 256
      dx = target.x + distance / 32 * round(cos(rad) * ceil(target.speed)) - @x
      dy = target.y + distance / 32 * round(sin(rad) * ceil(target.speed)) - @y
      direction = 256 - atan2(dy, dx) * 256 / (2*PI)
      @sim.spawn Shell, this, {direction}
    @haveTarget = yes
    @reload = 0

  # Take a shot at `@target`. We need to find the right angle to shoot at in order to hit a
  # possibly moving tank. We need to match up the X and Y coordinates of our shell and the tank
  # as a function of time:
  #     Xt + cos(At) * Vt * T = Xp + cos(Ap) * 32 * (T+1)
  #     Yt + sin(At) * Vt * T = Yp + sin(Ap) * 32 * (T+1)
  # `Xt`, `Yt`, `At`, and `Vt` are the tank's current position, angle and velocity.
  # `Xp`, `Yp`, are our current position. The shell speed is a constant 32. `T=0` is this moment.
  # We're trying to find `Ap`.
  fire: ->
    # FIXME
    @reload = 0

  takeShellHit: (shell) ->
    @armour = max(0, @armour - 1)
    @cell.retile()
    # FIXME: do something with speed

  takeExplosionHit: ->
    @armour = max(0, @armour - 5)
    @cell.retile()

SimPillbox.register()


#### Exports
module.exports = SimPillbox
