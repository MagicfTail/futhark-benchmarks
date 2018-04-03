#!/usr/bin/env python
#
# Simple frontend for the Ising model, that uses Pygame for
# visualisation.  If your Python is healthy, 'pip install pygame' (and
# maybe 'pip install numpy') should be all you need.  Maybe these
# packages are also available in your package system (they are pretty
# common).

from images import images

import numpy as np
import pygame
import time
import sys

images = images()
(width, height, _) = images.test_image_render()

size=(width, height)
pygame.init()
pygame.display.set_caption('Functional Images')

screen = pygame.display.set_mode(size)
surface = pygame.Surface(size, depth=32)
font = pygame.font.Font(None, 36)

def showText(what, where):
    text = font.render(what, 1, (255, 255, 255))
    screen.blit(text, where)

def render():
    futhark_start = time.time()
    (_, _, frame) = images.test_image_render()
    frame = frame.get()
    futhark_end = time.time()
    pygame.surfarray.blit_array(surface, frame)
    screen.blit(surface, (0, 0))
    speedmsg = "Futhark calls took %.2fms" % ((futhark_end-futhark_start)*1000)
    showText(speedmsg, (10, 10))
    pygame.display.flip()

pygame.key.set_repeat(500, 50)

while True:
    render()
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            sys.exit()
