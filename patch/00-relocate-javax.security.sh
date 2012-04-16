#!/bin/bash

mkdir -p org/apache/harmony/javax
mv javax/security org/apache/harmony/javax
find org/apache/harmony/ -name '*.java' -exec sed -i 's:package javax:package org.apache.harmony.javax:g' '{}' ';'
find -name '*.java' -exec sed -i 's:import javax.security.sasl:import org.apache.harmony.javax.security.sasl:g' '{}' ';'
find -name '*.java' -exec sed -i 's:import javax.security.auth:import org.apache.harmony.javax.security.auth:g' '{}' ';'

mkdir -p org
mv javax/jmdns org
find -name '*.java' -exec sed -i 's:javax.jmdns:org.jmdns:g' '{}' ';'

