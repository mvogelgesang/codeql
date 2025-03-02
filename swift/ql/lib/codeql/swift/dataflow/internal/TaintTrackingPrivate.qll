private import swift
private import DataFlowPrivate
private import TaintTrackingPublic
private import codeql.swift.dataflow.DataFlow
private import codeql.swift.dataflow.FlowSteps
private import codeql.swift.dataflow.Ssa
private import codeql.swift.controlflow.CfgNodes
private import FlowSummaryImpl as FlowSummaryImpl

/**
 * Holds if `node` should be a sanitizer in all global taint flow configurations
 * but not in local taint.
 */
predicate defaultTaintSanitizer(DataFlow::Node node) { none() }

cached
private module Cached {
  /**
   * Holds if the additional step from `nodeFrom` to `nodeTo` should be included
   * in all global taint flow configurations.
   */
  cached
  predicate defaultAdditionalTaintStep(DataFlow::Node nodeFrom, DataFlow::Node nodeTo) {
    // Flow through one argument of `appendLiteral` and `appendInterpolation` and to the second argument.
    // This is needed for string interpolation generated by the compiler. An interpolated string
    // like `"I am \(n) years old."` is represented as
    // ```
    // $interpolated = ""
    // appendLiteral(&$interpolated, "I am ")
    // appendInterpolation(&$interpolated, n)
    // appendLiteral(&$interpolated, " years old.")
    // ```
    exists(ApplyExpr apply, ExprCfgNode e |
      nodeFrom.asExpr() = [apply.getAnArgument().getExpr(), apply.getQualifier()] and
      apply.getStaticTarget().getName() = ["appendLiteral(_:)", "appendInterpolation(_:)"] and
      e.getExpr() = [apply.getAnArgument().getExpr(), apply.getQualifier()] and
      nodeTo.(PostUpdateNodeImpl).getPreUpdateNode().getCfgNode() = e
    )
    or
    // Flow from the computation of the interpolated string literal to the result of the interpolation.
    exists(InterpolatedStringLiteralExpr interpolated |
      nodeTo.asExpr() = interpolated and
      nodeFrom.asExpr() = interpolated.getAppendingExpr()
    )
    or
    // allow flow through string concatenation.
    exists(AddExpr ae |
      ae.getAnOperand() = nodeFrom.asExpr() and
      ae = nodeTo.asExpr() and
      ae.getType().getName() = "String"
    )
    or
    // flow through a subscript access
    exists(SubscriptExpr se |
      se.getBase() = nodeFrom.asExpr() and
      se = nodeTo.asExpr()
    )
    or
    // flow through the read of a content that inherits taint
    exists(DataFlow::ContentSet f |
      readStep(nodeFrom, f, nodeTo) and
      f.getAReadContent() instanceof TaintInheritingContent
    )
    or
    // flow through a flow summary (extension of `SummaryModelCsv`)
    FlowSummaryImpl::Private::Steps::summaryLocalStep(nodeFrom, nodeTo, false)
    or
    any(AdditionalTaintStep a).step(nodeFrom, nodeTo)
  }

  /**
   * Holds if taint propagates from `nodeFrom` to `nodeTo` in exactly one local
   * (intra-procedural) step.
   */
  cached
  predicate localTaintStepCached(DataFlow::Node nodeFrom, DataFlow::Node nodeTo) {
    DataFlow::localFlowStep(nodeFrom, nodeTo)
    or
    defaultAdditionalTaintStep(nodeFrom, nodeTo)
    or
    // Simple flow through library code is included in the exposed local
    // step relation, even though flow is technically inter-procedural
    FlowSummaryImpl::Private::Steps::summaryThroughStepTaint(nodeFrom, nodeTo, _)
  }
}

import Cached
