with open("escape_plan/Screens/HomeScreen.swift", "r") as f:
    c = f.read()

c = c.replace('secondary: item.id == "routes.corridors_clear"', 'secondary: item.id == "rescan.home"')
c = c.replace('onSecondary: item.id == "routes.corridors_clear"', 'onSecondary: item.id == "rescan.home"')

with open("escape_plan/Screens/HomeScreen.swift", "w") as f:
    f.write(c)

