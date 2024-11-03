#!/bin/bash

gleam build && ERL_LIBS=./ebin gleam run
