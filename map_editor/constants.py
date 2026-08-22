from networkx.algorithms.bipartite.basic import color

ALTITUDE_PALETTE = {
    # Глубины (Океан)
    "w-3": {'color': (10, 40, 80), 'alt': -3, 'legend': 'Глубоководная впадина', 'type': 'water'},
    "w-2": {'color': (25, 75, 140), 'alt': -2, 'legend': 'Открытый океан', 'type': 'water'},
    "w-1": {'color': (65, 125, 195), 'alt': -1, 'legend': 'Мелководье', 'type': 'water'},
    "w0": {'color': (85, 145, 205), 'alt': -1, 'legend': 'Мелководье (рифы)', 'type': 'water'},

    # Высоты (Суша)
    "l-1": {'color': (115, 150, 120), 'alt': -1, 'legend': 'Ниже уровня моря', 'type': 'land'},
    "l0": {'color': (115, 170, 115), 'alt': 0, 'legend': 'Низменности / Равнины', 'type': 'land'},
    "l+1": {'color': (175, 195, 130), 'alt': 1, 'legend': 'Предгорья', 'type': 'land'},
    "l+3": {'color': (190, 155, 95), 'alt': 2, 'legend': 'Низкие горы', 'type': 'land'},
    "l+4": {'color': (130, 95, 60), 'alt': 3, 'legend': 'Высокие горы', 'type': 'land'},
    "l+5": {'color': (82, 30, 15), 'alt': 4, 'legend': 'Снежные пики', 'type': 'land'},

    # Высоты (Ледник)
    "g-1": {'color': (100, 160, 170), 'alt': -1, 'legend': 'Плавучие льдины', 'type': 'ice'},
    "g0": {'color': (150, 160, 180), 'alt': 0, 'legend': 'Замерзший океан', 'type': 'ice'},
    "g+1": {'color': (175, 175, 175), 'alt': 1, 'legend': 'Замерзшие Предгорья', 'type': 'ice'},
    "g+3": {'color': (190, 190, 190), 'alt': 2, 'legend': 'Замерзшие горы', 'type': 'ice'},
    "g+4": {'color': (210, 210, 210), 'alt': 3, 'legend': 'Высокогорный ледник', 'type': 'ice'},
    "g+5": {'color': (240, 240, 255), 'alt': 4, 'legend': 'Айсхейм', 'type': 'ice'}
}
