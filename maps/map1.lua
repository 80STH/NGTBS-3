return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.12.1",
  class = "",
  orientation = "hexagonal",
  renderorder = "right-down",
  width = 11,
  height = 11,
  tilewidth = 14,
  tileheight = 12,
  nextlayerid = 5,
  nextobjectid = 2,
  hexsidelength = 6,
  staggeraxis = "y",
  staggerindex = "odd",
  properties = {},
  tilesets = {
    {
      name = "hex mini",
      firstgid = 1,
      class = "",
      tilewidth = 18,
      tileheight = 18,
      spacing = 0,
      margin = 0,
      columns = 5,
      image = "hexmini.png",
      imagewidth = 106,
      imageheight = 72,
      objectalignment = "unspecified",
      tilerendersize = "tile",
      fillmode = "stretch",
      tileoffset = {
        x = 0,
        y = 1
      },
      grid = {
        orientation = "orthogonal",
        width = 18,
        height = 18
      },
      properties = {},
      wangsets = {},
      tilecount = 20,
      tiles = {}
    },
    {
      name = "entities",
      firstgid = 21,
      class = "",
      tilewidth = 16,
      tileheight = 16,
      spacing = 0,
      margin = 0,
      columns = 9,
      image = "entities.png",
      imagewidth = 159,
      imageheight = 142,
      objectalignment = "unspecified",
      tilerendersize = "tile",
      fillmode = "stretch",
      tileoffset = {
        x = 0,
        y = 0
      },
      grid = {
        orientation = "orthogonal",
        width = 16,
        height = 16
      },
      properties = {},
      wangsets = {},
      tilecount = 72,
      tiles = {
        {
          id = 4,
          properties = {
            ["IsPlayable"] = false,
            ["MaxHealth"] = 5,
            ["Name"] = "Zombie"
          }
        }
      }
    }
  },
  layers = {
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 11,
      height = 11,
      id = 1,
      name = "terrain",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "base64",
      compression = "zlib",
      data = "eJyVziEOADAIA0AQSPr/586whDTAmKjqlWAiYhFtYpTcIeILO3k2GsYfNntNu64DuXwbhf+11b+Tx9JWjj1oe/sDT24CrQ=="
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 11,
      height = 11,
      id = 2,
      name = "entities",
      class = "",
      visible = false,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "base64",
      compression = "zlib",
      data = "eJyFj0EKwCAMBLeXeKggfU/P+/8vtYEIS4ytsATWYaIEwMh4cxZhyig6frB+WszZI/HO2cab3c528czZop9u5w65U1/H6r6CN6xuFOyd/sSCo/CQve2HpbzDNpzyOco+Yi4S8A=="
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 11,
      height = 11,
      id = 3,
      name = "status",
      class = "",
      visible = false,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "base64",
      compression = "zlib",
      data = "eJwLYmBgCBpkWHMImk1LN1OKAX8IJkg="
    }
  }
}
