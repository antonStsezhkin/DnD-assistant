import pygame
import pygame_gui
import sys

from map_editor.constants import ALTITUDE_PALETTE

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 720
TOOLBAR_WIDTH = 280

if __name__ == "__main__":
    pygame.init()
    pygame.font.init()

    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("Map Editor")
    clock = pygame.time.Clock()

    ui_manager = pygame_gui.UIManager((WINDOW_WIDTH, WINDOW_HEIGHT), 'theme.json')
    map_width = WINDOW_WIDTH - TOOLBAR_WIDTH
    toolbar_rect = pygame.Rect(map_width, 0, TOOLBAR_WIDTH, WINDOW_HEIGHT)

    toolbar_panel = pygame_gui.elements.UIPanel(
        relative_rect=toolbar_rect,
        starting_height=1,
        manager=ui_manager
    )

    # Оставлен один заголовок (дубликат удален для чистоты интерфейса)
    label = pygame_gui.elements.UILabel(
        relative_rect=pygame.Rect(10, 10, TOOLBAR_WIDTH - 20, 30),
        text="Панель Инструментов",
        manager=ui_manager,
        container=toolbar_panel
    )

    # 2. Создаем контейнер для вкладок
    tab_container = pygame_gui.elements.UITabContainer(
        relative_rect=pygame.Rect(10, 50, TOOLBAR_WIDTH - 20, WINDOW_HEIGHT - 120),
        manager=ui_manager,
        container=toolbar_panel
    )

    # 3. Динамическая группировка палитры
    unique_types = sorted(list(set(item['type'] for item in ALTITUDE_PALETTE.values())))
    brush_buttons = {}

    for t_type in unique_types:
        tab_name = t_type.capitalize()
        new_tab = tab_container.add_tab(title_text=tab_name)

        filtered_brushes = {k: v for k, v in ALTITUDE_PALETTE.items() if v['type'] == t_type}

        y_offset = 10
        for brush_id, info in filtered_brushes.items():
            btn = pygame_gui.elements.UIButton(
                relative_rect=pygame.Rect(10, y_offset, TOOLBAR_WIDTH - 60, 35),
                text=info['legend'],
                manager=ui_manager,
                container=tab_container.get_tab_container(new_tab)
            )
            brush_buttons[btn] = brush_id
            y_offset += 40

    # ИСПРАВЛЕНО: Заменено WINDOW_WIDTH на WINDOW_HEIGHT, чтобы кнопка не улетала вниз
    info_label = pygame_gui.elements.UILabel(
        relative_rect=pygame.Rect(10, WINDOW_HEIGHT - 60, TOOLBAR_WIDTH - 20, 40),
        text="Выбрано: Мелководье (w-1)",
        manager=ui_manager,
        container=toolbar_panel
    )

    current_brush_id = "w-1"
    drawn_tiles = []

    running = True
    while running:
        time_delta = clock.tick(60) / 1000.0
        mouse_pos = pygame.mouse.get_pos()

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

            ui_manager.process_events(event)

            if event.type == pygame_gui.UI_BUTTON_PRESSED:
                if event.ui_element in brush_buttons:
                    current_brush_id = brush_buttons[event.ui_element]
                    legend = ALTITUDE_PALETTE[current_brush_id]['legend']
                    info_label.set_text(f"Выбрано: {legend} ({current_brush_id})")

            # Рисование мышкой
            if event.type == pygame.MOUSEBUTTONDOWN or (
                    event.type == pygame.MOUSEMOTION and pygame.mouse.get_pressed()[0]):
                if mouse_pos[0] < map_width:
                    grid_x = (mouse_pos[0] // 32) * 32
                    grid_y = (mouse_pos[1] // 32) * 32

                    tile_pos = (grid_x, grid_y)
                    drawn_tiles = [t for t in drawn_tiles if t[0] != tile_pos]
                    drawn_tiles.append((tile_pos, current_brush_id))

        ui_manager.update(time_delta)

        screen.fill((30, 30, 30))

        # ИСПРАВЛЕНО: Отрегулированы границы сетки (линии рисуются строго на рабочей зоне)
        for x in range(0, map_width + 32, 32):
            pygame.draw.line(screen, (45, 45, 45), (x, 0), (x, WINDOW_HEIGHT))
        for y in range(0, WINDOW_HEIGHT, 32):
            pygame.draw.line(screen, (45, 45, 45), (0, y), (map_width, y))

        # Отрисовка тайлов
        for (tx, ty), b_id in drawn_tiles:
            color = ALTITUDE_PALETTE[b_id]['color']
            pygame.draw.rect(screen, color, (tx, ty, 32, 32))

        ui_manager.draw_ui(screen)

        # Отрисовка цветных квадратиков на кнопках тулбара
        for btn, b_id in brush_buttons.items():
            # Проверяем, активна ли сейчас вкладка, в которой лежит эта кнопка
            if btn.visible and btn.ui_container.visible:
                # Получаем абсолютные экранные координаты кнопки
                abs_rect = btn.get_abs_rect()
                # Считаем позицию квадрата внутри кнопки:
                # х: левый край кнопки + 10 пикселей отступа
                # y: центрируем квадрат 14x14 по вертикали относительно высоты кнопки
                square_x = abs_rect.x + 10
                square_y = abs_rect.y + (abs_rect.height - 14) // 2

                pygame.draw.rect(screen, ALTITUDE_PALETTE[b_id]['color'], (square_x, square_y, 14, 14))

        pygame.display.flip()

    pygame.quit()
    sys.exit()
