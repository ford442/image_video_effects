import sys; sys.argv=[sys.argv[0]]
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forkD_lenia_model import *
import numpy as np
for p0 in (0.0,0.5,1.0):
    for mu in (0.122,0.128,0.135,0.1525,0.17,0.178,0.185):
        o=run((p0,0.5,0.5,0.5),steps=700,mu_over=mu)
        print('R-slider',p0,'mu %.4f'%mu,'|',' | '.join('mean %.3f chg %.4f mid %.2f hf %.4f'%x for x in o),flush=True)
