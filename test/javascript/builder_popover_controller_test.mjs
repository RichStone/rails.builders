import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../app/javascript/controllers/builder_popover_controller.js", import.meta.url), "utf8")
const { default: BuilderPopoverController } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')).toString("base64")}`)

function popover(open = false) {
  const controller = new BuilderPopoverController()
  controller.element = { open }
  controller.triggerTarget = {
    attributes: {},
    focused: false,
    setAttribute(name, value) { this.attributes[name] = value },
    focus() { this.focused = true }
  }
  return controller
}

test("opens only for mouse hover and keeps native tap state in sync", () => {
  const controller = popover()
  controller.connect()
  assert.equal(controller.triggerTarget.attributes["aria-expanded"], "false")

  controller.openOnHover({ pointerType: "touch" })
  assert.equal(controller.element.open, false)

  controller.openOnHover({ pointerType: "mouse" })
  assert.equal(controller.element.open, true)
  controller.sync()
  assert.equal(controller.triggerTarget.attributes["aria-expanded"], "true")

  controller.closeAfterHover()
  assert.equal(controller.element.open, false)

  controller.element.open = true
  controller.openOnHover({ pointerType: "mouse" })
  controller.closeAfterHover()
  assert.equal(controller.element.open, true, "leaving hover does not close a popover opened by click")
})

test("backdrop click closes and returns focus to the trigger", () => {
  const controller = popover(true)
  let prevented = false
  controller.close({ type: "click", preventDefault() { prevented = true } })

  assert.equal(prevented, true)
  assert.equal(controller.element.open, false)
  assert.equal(controller.triggerTarget.attributes["aria-expanded"], "false")
  assert.equal(controller.triggerTarget.focused, true)
})
