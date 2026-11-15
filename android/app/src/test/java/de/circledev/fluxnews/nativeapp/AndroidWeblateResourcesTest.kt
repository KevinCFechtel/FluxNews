package de.circledev.fluxnews.nativeapp

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

class AndroidWeblateResourcesTest {
    private val resources = File("src/main/res")

    private fun parse(path: File): List<Element> {
        val builder = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        val root = builder.parse(path).documentElement
        assertEquals("resources", root.tagName)
        val nodes = root.childNodes
        return (0 until nodes.length).mapNotNull { nodes.item(it) as? Element }
    }

    @Test fun allSevenProductLocaleCatalogsArePresent() {
        val english = File(resources, "values/strings.xml")
        assertTrue(english.path, english.isFile)
        for (locale in listOf("de", "es", "gl", "nl", "ta", "tr")) {
            val file = File(resources, "values-$locale/strings.xml")
            assertTrue(file.path, file.isFile)
            assertTrue(parse(file).all { it.tagName in setOf("string", "plurals") })
        }
    }

    @Test fun sourceKeysAreUniqueAndPluralEntriesAreStructured() {
        val entries = parse(File(resources, "values/strings.xml"))
        val names = entries.map { it.getAttribute("name") }
        assertFalse(names.any(String::isBlank))
        assertEquals(names.size, names.toSet().size)
        val plurals = entries.filter { it.tagName == "plurals" }
        assertTrue(plurals.isNotEmpty())
        assertTrue(plurals.all { entry ->
            val items = entry.getElementsByTagName("item")
            (0 until items.length).any { items.item(it).attributes.getNamedItem("quantity")?.nodeValue == "other" }
        })
        assertTrue(names.containsAll(listOf("nav_feeds", "nav_add_feed", "feed_discovery_empty", "action_cancel")))
    }
}
