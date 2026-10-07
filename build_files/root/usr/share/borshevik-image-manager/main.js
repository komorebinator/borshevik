#!/usr/bin/env gjs

import System from 'system';

import { Application } from './application.js';

// GApplication takes the program's name first, as in C's argv; gjs's ARGV
// leaves it out, and without it the first option would be taken for the name.
const app = new Application();
app.run([System.programInvocationName, ...ARGV]);
